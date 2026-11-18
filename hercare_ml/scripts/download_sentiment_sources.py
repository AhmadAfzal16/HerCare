"""Download attributed public sentiment benchmarks, not clinical distress labels."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'data' / 'raw' / 'sentiment'
SOURCES = [
    {'id': 'uci_english', 'file': 'english.zip', 'license': 'CC-BY-4.0',
     'citation': 'https://doi.org/10.24432/C57604',
     'url': 'https://archive.ics.uci.edu/static/public/331/sentiment+labelled+sentences.zip',
     'annotation': 'Published positive/negative general reviews; no neutral or clinical labels'},
    {'id': 'uci_roman_urdu', 'file': 'roman_urdu.zip', 'license': 'CC-BY-4.0',
     'citation': 'https://doi.org/10.24432/C58325',
     'url': 'https://archive.ics.uci.edu/static/public/458/roman+urdu+data+set.zip',
     'annotation': 'General sentiment comments; not postpartum distress'},
    {'id': 'urdu_multidomain', 'file': 'urdu.csv', 'license': 'CC0-1.0',
     'citation': 'https://huggingface.co/datasets/umar178/UrduMultiDomainClassification',
     'url': 'https://huggingface.co/datasets/umar178/UrduMultiDomainClassification/resolve/da5a04db5f68457204b3ced9caa457a26bbd9d48/Dataset%20-%20Sheet1.csv',
     'annotation': 'Uploader-declared sentiment; annotation methodology not documented. Research only, requires human audit'},
]


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    for source in SOURCES:
        path = ROOT / source['file']
        if not path.exists():
            with urllib.request.urlopen(source['url'], timeout=30) as response:
                content = response.read(12 * 1024 * 1024 + 1)
            if len(content) > 12 * 1024 * 1024 or not content or content.lstrip().startswith(b'<!'):
                raise ValueError('Invalid sentiment source response')
            with path.open('xb') as stream:
                stream.write(content)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        metadata_path = path.with_suffix(path.suffix + '.provenance.json')
        if metadata_path.exists():
            if json.loads(metadata_path.read_text())['sha256'] != digest:
                raise ValueError('Existing source changed; do not silently replace it')
        else:
            metadata_path.write_text(json.dumps({**source, 'sha256': digest, 'bytes': path.stat().st_size,
                'clinical_labels': False}, indent=2), encoding='utf-8')
        print(f"{source['id']}: {path.stat().st_size} bytes; sha256={digest}")


if __name__ == '__main__':
    main()
