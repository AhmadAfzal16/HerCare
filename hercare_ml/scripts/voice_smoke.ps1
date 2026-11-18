param([string]$Python = '.venv\Scripts\python.exe')
$ErrorActionPreference = 'Stop'
# Artificial fixture only. Explicit file output prevents audible speech playback.
Add-Type -AssemblyName System.Speech
$fixtureDirectory = Join-Path $PSScriptRoot '..\artifacts\test_runs\voice_smoke'
New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
$fixturePath = Join-Path $fixtureDirectory 'synthetic_english.wav'
$synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $synthesizer.SetOutputToWaveFile($fixturePath)
    $synthesizer.Speak('Today I feel calm. My family is helping me.')
} finally { $synthesizer.Dispose() }
& $Python -X utf8 -c "import sys,time,json,pathlib; from app.voice_transcription import transcribe; start=time.monotonic(); result=transcribe(pathlib.Path(sys.argv[1]).read_bytes(),'audio/wav','en'); assert result['status']=='draft' and result['review_required']; assert 'calm' in result['text'].lower(), result; print(json.dumps({'synthetic_text':result['text'],'seconds':round(time.monotonic()-start,2),'model':result['model_version']}))" $fixturePath
if ($LASTEXITCODE -ne 0) { throw 'Synthetic ASR smoke check failed.' }
