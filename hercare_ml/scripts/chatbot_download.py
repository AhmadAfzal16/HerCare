"""Provision checksum-pinned local models/runtime, never a cloud inference key.

Downloads ~2.50GB model plus ~20MB CPU runtime; performs no model/server launch.
Only public operator-owned artifacts are written. Existing outputs are verified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1] / 'artifacts' / 'chatbot'
MODEL = {'file': 'qwen3_4b_q4.gguf', 'bytes': 2497281120,
         'sha256': '3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597',
         'url': 'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
         'license': 'Apache-2.0', 'base_model': 'Qwen/Qwen3-4B-Instruct-2507', 'quantization_provider': 'unsloth',
         'clinical_validation': False, 'finetuned_for_hercare': False}
RUNTIME = {'file': 'llama-b11510-bin-win-cpu-x64.zip', 'bytes': 19485794,
           'sha256': 'e56a5c6713751e5b5943271558a8abe46e83e0602232ba32a71d2dea789d8fe9',
           'url': 'https://github.com/ggml-org/llama.cpp/releases/download/b11510/llama-b11510-bin-win-cpu-x64.zip',
           'license': 'MIT', 'version': 'b11510'}


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def download(source, directory):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / source['file']
    if path.exists():
        if path.stat().st_size != source['bytes'] or digest(path) != source['sha256']:
            raise ValueError('Existing artifact differs; do not silently overwrite it')
        return path
    partial = path.with_suffix(path.suffix + '.part')
    if partial.exists():
        raise FileExistsError('Partial download exists; inspect it before a retry')
    received = 0
    request = urllib.request.Request(source['url'], headers={'User-Agent': 'HerCare-research-provisioning/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response, partial.open('xb') as stream:
        while chunk := response.read(4 * 1024 * 1024):
            received += len(chunk)
            if received > source['bytes']:
                raise ValueError('Download exceeds declared artifact size')
            stream.write(chunk)
            if received // (100 * 1024 * 1024) != (received-len(chunk)) // (100 * 1024 * 1024):
                print(f'{source["file"]}: {received // (1024*1024)} MiB received', flush=True)
    if received != source['bytes'] or digest(partial) != source['sha256']:
        raise ValueError('Artifact checksum/size failed; partial retained for inspection')
    with partial.open('rb') as stream:
        if stream.read(4) not in {b'GGUF', b'PK\x03\x04'}:
            raise ValueError('Invalid artifact file signature')
    partial.rename(path)
    path.with_suffix(path.suffix + '.provenance.json').write_text(json.dumps(source, indent=2), encoding='utf-8')
    print(f'Verified {source["file"]}; sha256={source["sha256"]}', flush=True)
    return path


def provision(runtime_only=False):
    archive = download(RUNTIME, ROOT / 'downloads')
    folder = ROOT / 'runtime' / RUNTIME['version']
    if not folder.exists():
        folder.mkdir(parents=True)
        with zipfile.ZipFile(archive) as source:
            if sum(info.file_size for info in source.infolist()) > 300 * 1024 * 1024:
                raise ValueError('Unexpected expanded runtime size')
            for info in source.infolist():
                target = (folder / info.filename).resolve()
                if not target.is_relative_to(folder.resolve()) or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Unsafe archive entry')
            source.extractall(folder)
    if not runtime_only:
        download(MODEL, ROOT / 'models')
    print('Provisioned only. No chatbot/app/server was started.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-only', action='store_true')
    provision(parser.parse_args().runtime_only)
