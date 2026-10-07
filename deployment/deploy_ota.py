"""Run on VPS with a staged IPA/page/manifest. Keeps rollback copies and versioned assets."""
import hashlib,json,os,pathlib,plistlib,shutil,sys,time,zipfile
source=pathlib.Path(sys.argv[1]).resolve()
target=pathlib.Path('/var/www/ke-ota')
expected=json.loads((source/'expected.json').read_text())
for name,digest in expected['before'].items():
 assert hashlib.sha256((target/name).read_bytes()).hexdigest()==digest, 'Concurrent OTA change: '+name
ipa=source/'KeApp.ipa'
assert hashlib.sha256(ipa.read_bytes()).hexdigest()==expected['ipa_sha256']
with zipfile.ZipFile(ipa) as z:
 name=next(n for n in z.namelist() if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/')==2)
 info=plistlib.loads(z.read(name))
version=info['CFBundleVersion']
assert info['CFBundleIdentifier']=='love.jiagude.ke' and version.isdecimal()
previous=plistlib.loads((target/'manifest.plist').read_bytes())['items'][0]['metadata']['bundle-version']
assert int(version)>int(previous), 'Refuse same or older build'
manifest=plistlib.loads((source/'manifest.plist').read_bytes())['items'][0]
assert manifest['metadata']['bundle-version']==version
assert manifest['metadata']['bundle-identifier']==info['CFBundleIdentifier']
assert manifest['assets'][0]['url'].endswith('/KeApp-'+version+'.ipa')
html=(source/'index.html').read_text()
assert 'Build '+version in html and '%2Fmanifest-'+version+'.plist' in html
backup=pathlib.Path('/root/ota-deploy-backups/'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-build'+version)
backup.mkdir(parents=True,mode=0o700)
for name in ['index.html','manifest.plist','KeApp.ipa']:shutil.copy2(target/name,backup/name)
for name in ['KeApp-'+version+'.ipa','manifest-'+version+'.plist']:assert not (target/name).exists(), 'Versioned asset already exists'
def publish(src,dst):
 temp=dst.with_name(dst.name+'.new')
 shutil.copyfile(src,temp);os.chmod(temp,0o644);os.replace(temp,dst)
try:
 publish(ipa,target/('KeApp-'+version+'.ipa'))
 publish(source/'manifest.plist',target/('manifest-'+version+'.plist'))
 publish(ipa,target/'KeApp.ipa')
 publish(source/'manifest.plist',target/'manifest.plist')
 # Page switched last, after the immutable versioned package and manifest exist.
 publish(source/'index.html',target/'index.html')
 assert hashlib.sha256((target/('KeApp-'+version+'.ipa')).read_bytes()).hexdigest()==expected['ipa_sha256']
 print('OTA_DEPLOY_OK',version,backup)
except Exception:
 for name in ['index.html','manifest.plist','KeApp.ipa']:publish(backup/name,target/name)
 raise
