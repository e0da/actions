const test = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const workflow = JSON.parse(execFileSync('ruby', ['-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(".github/workflows/ci-elixir-verified.yml"))'], {encoding:'utf8'}));
const steps = workflow.jobs.mix.steps;
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
function script(name) { return steps.find(s => s.name === name).with.script; }
async function verify({proof = {key:'k', tree:'t', repository:'e0da/stack', run_id:10, job_id:20}, job = {run_id:10, status:'completed', conclusion:'success', steps:[{name:'Run CI', status:'completed', conclusion:'success'}], html_url:'proof-url'}} = {}) {
  const outputs = {};
  const core = {setOutput:(k,v)=>outputs[k]=v, summary:{addRaw:()=>({write:async()=>{}})}};
  await new AsyncFunction('require','process','core','github','context', script('Verify prior successful native job'))(
    name => {assert.equal(name,'node:fs'); return {readFileSync:()=>JSON.stringify(proof)};},
    {env:{PROOF_FILE:'receipt', PROOF_KEY:'k', PROOF_TREE:'t'}}, core,
    {rest:{actions:{getJobForWorkflowRun:async args=>{assert.equal(args.job_id,20);return {data:job};}}}},
    {repo:{owner:'e0da',repo:'stack'}});
  return outputs.reused;
}
test('successful prior native execution is reusable', async()=>assert.equal(await verify(),'true'));
for(const conclusion of ['failure','cancelled','skipped','timed_out',null]) test(`does not reuse ${conclusion} job`,async()=>assert.equal(await verify({job:{run_id:10,status:'completed',conclusion,steps:[]}}),'false'));
test('does not reuse unfinished job',async()=>assert.equal(await verify({job:{run_id:10,status:'in_progress',conclusion:null,steps:[]}}),'false'));
test('does not reuse a receipt from a different run',async()=>assert.equal(await verify({job:{run_id:11,status:'completed',conclusion:'success',steps:[]}}),'false'));
test('successful skipped-proof job cannot become native evidence',async()=>assert.equal(await verify({job:{run_id:10,status:'completed',conclusion:'success',steps:[{name:'Run CI',status:'completed',conclusion:'skipped'}]}}),'false'));
for(const [field,value] of [['key','wrong'],['tree','wrong'],['repository','other/repo']]) test(`rejects mismatched ${field}`,async()=>assert.rejects(()=>verify({proof:{key:'k',tree:'t',repository:'e0da/stack',run_id:10,job_id:20,[field]:value}}),/identity/));
test('API errors cannot credit success',async()=>assert.rejects(()=>new AsyncFunction('require','process','core','github','context',script('Verify prior successful native job'))(()=>({readFileSync:()=>JSON.stringify({key:'k',tree:'t',repository:'e0da/stack',job_id:20})}),{env:{PROOF_KEY:'k',PROOF_TREE:'t'}},{},{rest:{actions:{getJobForWorkflowRun:async()=>{throw Error('403');}}}},{repo:{owner:'e0da',repo:'stack'}}),/403/));
test('only verified success bypasses setup and execution',()=>{
 for(const name of ['Identify immutable toolchain cache','Cache downloaded BEAM tools','Set up BEAM','Verify preinstalled BEAM','Cache Mix deps','Configure private git deps (SSH)','Install deps','Run CI']) assert.match(steps.find(s=>s.name===name).if,/steps.proof.outputs.reused != 'true'/,name);
 assert.match(steps.find(s=>s.id==='proof-key').if,/PRIVATE_DEPS_SSH_KEY == ''/);
 assert.equal((workflow.on||workflow.true).workflow_call.inputs['result-reuse-environment'].default,'');
 for(const name of ['Record native execution receipt','Save native execution receipt']) assert.match(steps.find(s=>s.name===name).if,/proof-cache.outputs.cache-hit != 'true'/);
});
const policy = {'beam-mode':'setup-beam','otp-version':'29.0.2','elixir-version':'1.20.1','result-reuse-environment':'ghcr.io/e0da/runner@sha256:'+'c'.repeat(64)};
async function identify(refs,tree='tree',platform='Linux-ARM64',inputs=JSON.stringify(policy)) {
 const out={};
 const fakeRequire=name=>name==='node:child_process'?{execFileSync:(_,args)=>args[0]==='show'?refs.map(ref=>`uses: e0da/actions/.github/workflows/ci-elixir-verified.yml@${ref}`).join('\n'):tree}:require(name);
 await new AsyncFunction('require','process','core',script('Identify tested tree and execution contract'))(fakeRequire,{env:{CALLER_WORKFLOW:'e0da/stack/.github/workflows/mcog.yml@refs/pull/1/merge',REUSE_INPUTS:inputs,PROOF_PLATFORM:platform}},{setOutput:(k,v)=>out[k]=v});return out;
}
test('tree, platform, commands and reusable revision all invalidate proof',async()=>{
 const sha='a'.repeat(40),old=(await identify([sha])).key;
 for(const args of [[[sha],'other'],[[sha],'tree','Linux-X64'],[[sha],'tree','Linux-ARM64',JSON.stringify({...policy,'ci-command':'changed'})],[['b'.repeat(40)]]]) assert.notEqual((await identify(...args)).key,old);
});
for(const refs of [[],['main'],['a'.repeat(40),'b'.repeat(40)]]) test(`rejects ambiguous or mutable caller ${refs}`,async()=>assert.rejects(()=>identify(refs),/immutable/));

for(const change of [{'beam-mode':'runner-preinstalled'},{'otp-version':'29'},{'elixir-version':'1.20'},{'result-reuse-environment':'runner:latest'}]) test(`rejects unqualified environment ${JSON.stringify(change)}`,async()=>assert.rejects(()=>identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify({...policy,...change})),/exact downloaded/));
test('original native commands, cache paths and input defaults are preserved',()=>{
 const original=JSON.parse(execFileSync('ruby',['-ryaml','-rjson','-e','puts JSON.generate(YAML.load_file(".github/workflows/ci-elixir.yml"))'],{encoding:'utf8'}));
 for(const [name,input] of Object.entries((original.on||original.true).workflow_call.inputs)) assert.deepEqual((workflow.on||workflow.true).workflow_call.inputs[name],input,name);
 for(const before of original.jobs.mix.steps) {
   const after=steps.find(s=>before.name?s.name===before.name:s.uses===before.uses);
   assert.ok(after,before.name||before.uses);
   const copy={...after};delete copy.if;
   const expected={...before};delete expected.if;
   assert.deepEqual(copy,expected,before.name||before.uses);
 }
});
for(const count of [0,1,2]) test(`receipt requires unique active runner job (${count})`,async()=>{
 let saved;
 const call=()=>new AsyncFunction('require','process','github','context',script('Record native execution receipt'))(()=>({writeFileSync:(_,s)=>saved=JSON.parse(s)}),{env:{GITHUB_RUN_ATTEMPT:'1',PROOF_RUNNER:'runner',PROOF_KEY:'k',PROOF_TREE:'t',PROOF_FILE:'receipt'}},{paginate:async()=>Array.from({length:count},(_,i)=>({id:i+20,status:'in_progress',runner_name:'runner'})),rest:{actions:{listJobsForWorkflowRunAttempt(){}}}},{repo:{owner:'e0da',repo:'stack'},runId:10});
 if(count===1) {await call();assert.deepEqual(saved,{key:'k',tree:'t',repository:'e0da/stack',run_id:10,job_id:20});} else await assert.rejects(call,/uniquely/);
});
