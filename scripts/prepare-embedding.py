"""Build-time download only. Runtime embedding never accesses the network."""
from pathlib import Path
import hashlib
import json
import sys
from huggingface_hub import snapshot_download
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'PlannerRuntime'))
from memory import MODEL, REVISION
output = Path(sys.argv[1])
snapshot_download(MODEL, revision=REVISION, local_dir=output,
                  allow_patterns=['onnx/model.onnx', 'tokenizer.json', 'README.md'])
manifest = {'model':MODEL, 'revision':REVISION, 'pooling':'cls', 'normalize':True, 'dimensions':384,
            'sha256':{name:hashlib.sha256((output / name).read_bytes()).hexdigest()
                      for name in ('tokenizer.json','onnx/model.onnx')}}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
