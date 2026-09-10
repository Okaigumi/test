import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { request } from 'node:http';
import { createStaticServer } from './static-server.mjs';

test('dummy-only HTTP boundary and private-path regression', async t => {
  const temp = await mkdtemp(join(tmpdir(), 'okg-http-dummy-'));
  const root = join(temp, 'public');
  const sibling = join(temp, 'public-private');
  await mkdir(root); await mkdir(sibling);
  for (const dir of ['backups', '.git', 'assets', 'secrets', 'scripts', 'docs']) await mkdir(join(root,dir));
  for (const name of ['index.html','assets/a.css','assets/a.js','assets/a.json','assets/a.csv','assets/a.svg']) {
    await writeFile(join(root,name),'PUBLIC_DUMMY');
  }
  for (const name of ['.env.backup.local','backups/dummy.zip','.git/config','secrets/dummy.json','scripts/dummy.js','docs/dummy.html']) {
    await writeFile(join(root,name),'PRIVATE_DUMMY_DO_NOT_SERVE');
  }
  await writeFile(join(sibling,'index.html'),'PRIVATE_DUMMY_DO_NOT_SERVE');
  // Windows junctions require no administrator privileges. Only dummy targets.
  await symlink(sibling, join(root,'outside'), 'junction');
  await symlink(join(root,'secrets'), join(root,'alias'), 'junction');
  const server = await createStaticServer({root});
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  function fetchRaw(path, method) {
    return new Promise((resolve,reject)=>{
      const req=request({host:'127.0.0.1',port:server.address().port,path,method},res=>{
        let body='';res.on('data',chunk=>body+=chunk);res.on('end',()=>resolve({status:res.statusCode,body}));
      }); req.on('error',reject);req.end();
    });
  }
  let checks=0;
  for (const method of ['GET','HEAD']) {
    for (const path of ['/','/index.html','/assets/a.css','/assets/a.js','/assets/a.json','/assets/a.csv','/assets/a.svg']) {
      const res=await fetchRaw(path,method); assert.equal(res.status,200,`${method} ${path}`);
      assert.equal(res.body,method==='HEAD'?'':'PUBLIC_DUMMY');checks++;
    }
    for (const path of ['/.env.backup.local','/.ENV.BACKUP.LOCAL','/%2eenv.backup.local','/backups/dummy.zip',
      '/BACKUPS/dummy.zip','/.git/config','/secrets/dummy.json','/scripts/dummy.js','/docs/dummy.html',
      '/../public-private/index.html','/%2e%2e%2fpublic-private/index.html','/..%5cpublic-private%5cindex.html',
      '/assets/../../public-private/index.html','/%252e%252e%252fpublic-private/index.html',
      '/outside/index.html','/alias/dummy.json','/index.html:stream','/.env.backup.local.','//public-private/index.html']) {
      const res=await fetchRaw(path,method); assert.ok([403,404].includes(res.status),`${method} ${path}: ${res.status}`);
      assert.ok(!res.body.includes('PRIVATE_DUMMY')); if(method==='HEAD') assert.equal(res.body,'');checks++;
    }
  }
  assert.equal((await fetchRaw('/index.html','POST')).status,405);checks++;
  assert.equal((await fetchRaw('/%zz','GET')).status,400);checks++;
  t.diagnostic(`${checks} HTTP assertions passed; dummy fixture: ${temp}`);
});
