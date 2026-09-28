const {
  S3Client,
  PutObjectCommand,
  HeadObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const speech = require('@google-cloud/speech');
const { AppError } = require('../../middleware/error_handler');

const MAX_VOICE_BYTES = 4 * 1024 * 1024;

function storageConfig() {
  const bucket = process.env.JOURNAL_AUDIO_BUCKET;
  const region = process.env.AWS_REGION;
  if (!bucket || !region) {
    throw new AppError('Voice journals are not configured on this deployment.', 503);
  }
  return { bucket, region };
}

function s3Client(region) {
  return new S3Client({
    region,
    endpoint: process.env.S3_ENDPOINT || undefined,
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
  });
}

async function createUploadUrl({ motherId, journalId, contentLength }) {
  const { bucket, region } = storageConfig();
  if (contentLength < 1 || contentLength > MAX_VOICE_BYTES) {
    throw new AppError('Voice recording must be smaller than 4 MB.', 422);
  }
  const objectKey = `private-journals/${motherId}/${journalId}.wav`;
  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: objectKey,
    ContentType: 'audio/wav',
    ContentLength: contentLength,
    ServerSideEncryption: 'AES256',
    Metadata: { owner: motherId, journal: journalId },
  });
  const uploadUrl = await getSignedUrl(s3Client(region), command, { expiresIn: 300 });
  return {
    objectKey,
    uploadUrl,
    expiresInSeconds: 300,
    headers: {
      'Content-Type': 'audio/wav',
      'x-amz-server-side-encryption': 'AES256',
    },
  };
}

async function downloadVerifiedAudio(objectKey, expectedBytes) {
  const { bucket, region } = storageConfig();
  const client = s3Client(region);
  const head = await client.send(new HeadObjectCommand({ Bucket: bucket, Key: objectKey }));
  if (!head.ContentLength || head.ContentLength !== expectedBytes || head.ContentLength > MAX_VOICE_BYTES) {
    throw new AppError('Uploaded voice recording failed integrity validation.', 422);
  }
  if (head.ContentType !== 'audio/wav') {
    throw new AppError('Unsupported voice recording format.', 422);
  }
  const object = await client.send(new GetObjectCommand({ Bucket: bucket, Key: objectKey }));
  return Buffer.from(await object.Body.transformToByteArray());
}

async function transcribeAudio(audio, preferredLanguage = 'ur') {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.GOOGLE_CLOUD_PROJECT) {
    throw new AppError('Voice transcription is not configured on this deployment.', 503);
  }
  const languageCode = preferredLanguage === 'en' ? 'en-US' : 'ur-PK';
  const alternativeLanguageCodes = preferredLanguage === 'en' ? ['ur-PK'] : ['en-US'];
  const client = new speech.SpeechClient();
  const [response] = await client.recognize({
    audio: { content: audio.toString('base64') },
    config: {
      encoding: 'LINEAR16',
      sampleRateHertz: 16000,
      audioChannelCount: 1,
      languageCode,
      alternativeLanguageCodes,
      enableAutomaticPunctuation: true,
      model: 'latest_long',
    },
  });
  return (response.results || [])
    .map((result) => result.alternatives?.[0]?.transcript || '')
    .join(' ')
    .trim();
}

async function deleteAudio(objectKey) {
  if (!objectKey) return;
  const { bucket, region } = storageConfig();
  await s3Client(region).send(new DeleteObjectCommand({ Bucket: bucket, Key: objectKey }));
}

module.exports = {
  MAX_VOICE_BYTES,
  createUploadUrl,
  downloadVerifiedAudio,
  transcribeAudio,
  deleteAudio,
};
