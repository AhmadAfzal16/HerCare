"""Ephemeral CPU inference checks using original synthetic queries, no server.

This checks local runtime/structured routing, not clinical efficacy or LLM
fine-tuning. It never reads real app conversations or launches the application.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

from app.chatbot.retrieval import load_cards
from app.chatbot.local_generation import SYSTEM_INSTRUCTIONS, evidence_catalog
from scripts.chatbot_download import ROOT, MODEL, digest

CASES = [
    ('en', 'I cannot bond with my baby', 'bonding'),
    ('ur', 'بچے سے تعلق نہیں بن رہا', 'bonding'),
    ('roman_ur', 'bache se bond nahi ban raha', 'bonding'),
    ('en', 'when do I take EPDS', 'tests'),
    ('ur', 'ای پی ڈی ایس کب کرنا ہے', 'tests'),
    ('roman_ur', 'epds kab karna hai', 'tests'),
]


def evaluate(output):
    if output.exists():
        raise FileExistsError('Use a fresh evaluation directory')
    executable = ROOT / 'runtime' / 'b11510' / 'llama-completion.exe'
    model = ROOT / 'models' / MODEL['file']
    if not executable.is_file() or not model.is_file() or digest(model) != MODEL['sha256']:
        raise ValueError('Provisioned trusted runtime/model required')
    cards, knowledge_hash = load_cards()
    ids = [card['id'] for card in cards]
    grammar = {'type':'object','properties':{'evidence_id':{'enum':ids+[None]}},
               'required':['evidence_id'],'additionalProperties':False}
    results = []
    output.mkdir(parents=True, exist_ok=False)
    for language, question, expected in CASES:
        # Public source-checked cards and authored questions only; temporary prompt
        # files are not a production prompt cache or user-data logging mechanism.
        evidence = evidence_catalog(cards, language)
        instruction = SYSTEM_INSTRUCTIONS + '\nEvidence: ' + json.dumps(evidence, ensure_ascii=False)
        prompt = f'<|im_start|>system\n{instruction}<|im_end|>\n<|im_start|>user\n{question}<|im_end|>\n<|im_start|>assistant\n'
        with tempfile.TemporaryDirectory(prefix='synthetic-prompt-', dir=output) as temp:
            path = Path(temp) / 'prompt.txt'
            path.write_text(prompt, encoding='utf-8')
            started = time.monotonic()
            process = subprocess.run([str(executable), '-m', str(model), '-f', str(path),
                '-n','40','-c','4096','-t','4','-ngl','0','--temp','.2','--seed','42',
                '--no-conversation','--no-display-prompt','--color','off','--log-colors','off','--no-warmup',
                '--json-schema',json.dumps(grammar)], capture_output=True, text=True,
                encoding='utf-8', errors='replace', timeout=180)
            elapsed = time.monotonic() - started
        match = re.search(r'\{\s*"evidence_id"\s*:\s*(?:"[^"]+"|null)\s*\}', process.stdout + '\n' + process.stderr)
        predicted = json.loads(match[0])['evidence_id'] if match else None
        item = {'language':language,'expected':expected,'predicted':predicted,
                'exit_code':process.returncode,'elapsed_seconds':round(elapsed,2),
                'output_chars':len(process.stdout),'diagnostic_chars':len(process.stderr),
                'structured_output':match is not None, 'correct':predicted==expected}
        results.append(item)
        print(json.dumps(item), flush=True)
    report = {'model':MODEL['base_model'],'quantization':'Q4_K_M','model_sha256':MODEL['sha256'],
              'knowledge_sha256':knowledge_hash,'runtime':'llama.cpp b11510 CPU Windows x64',
              'threads':4,'context_tokens':4096,'cases':results,
              'prompt_policy':'compact_evidence_selector_v1',
              'correct':sum(row['correct'] for row in results),'total':len(results),
              'validation_status':'synthetic_runtime_smoke_only','clinical_validation':False,
              'llm_finetuned':False,'limitations':['Six declared authored routing cases, not an independent clinical benchmark.',
                 'Each run reloads model; cold latency is not a steady-state deployed p95 measurement.',
                 'No server/app launch or end-to-end deployed-network test.']}
    (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir',type=Path,required=True)
    evaluate(parser.parse_args().output_dir)
