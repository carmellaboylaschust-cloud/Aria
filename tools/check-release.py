"""Scan the publish allowlist; print categories and paths, never matched secrets."""
from pathlib import Path
import re, json, hashlib, sys
ROOT=Path(__file__).resolve().parents[1]
TOP={'README.md','LICENSE','NOTICE.md','SECURITY.md','PRIVACY.md','CONTRIBUTING.md','.gitignore','.gitattributes'}
FOLDERS={'docs','tests','tools','launcher'}
EXTS={'.md','.ps1','.py','.mjs','.js','.cs','.css','.html','.json','.svg'}
def selected():
    result=[]
    for p in ROOT.rglob('*'):
        rel=p.relative_to(ROOT)
        if rel.parts[0] in {'.git','.test-output','node_modules'} or '__pycache__' in rel.parts:continue
        if p.is_symlink():raise ValueError('symlink: '+str(rel))
        if not p.is_file():continue
        ok=(len(rel.parts)==1 and p.name in TOP) or (rel.parts[0] in FOLDERS and p.suffix in EXTS)
        if rel.parts[0]=='engine':
            ok=(len(rel.parts)==2 and p.name=='VERSION') or (len(rel.parts)==3 and rel.parts[1] in {'scripts','assets','hub'} and p.suffix in EXTS) or (len(rel.parts)==4 and rel.parts[1:3]==('hub','media') and p.suffix=='.svg') or str(rel).replace('\\','/')=='engine/assets/aria-salt.png'
        if not ok:raise ValueError('File outside public allowlist: '+str(rel))
        result.append(p)
    return sorted(result)
def scan(files):
    patterns={
      'private-key':r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
      'github-token':r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
      'service-key':r'\bsk-[A-Za-z0-9_-]{32,}',
      'local-user-path':r'(?i)[A-Z]:[\\/]+Users[\\/]+(?!Public\b|Default\b)[^\\/\s\x27\x22]+',
      'wechat-id':r'\bwxid_[a-z0-9_]{8,}',
      'private-state':r'(?i)"(?:access_token|refresh_token|session_token)"\s*:\s*"[^"\s]{12,}"',
    }
    hits=[]
    for p in files:
        if p.suffix=='.png':continue
        text=p.read_text(encoding='utf-8-sig')
        for category,pat in patterns.items():
            for m in re.finditer(pat,text):hits.append({'file':p.relative_to(ROOT).as_posix(),'line':text[:m.start()].count('\n')+1,'category':category})
    return hits
if __name__=='__main__':
    files=selected();hits=scan(files)
    print(json.dumps({'files':len(files),'bytes':sum(p.stat().st_size for p in files),'findings':hits},ensure_ascii=False))
    sys.exit(bool(hits))
