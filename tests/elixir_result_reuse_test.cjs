const test = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const [workflow, original] = JSON.parse(execFileSync('ruby', ['-ryaml', '-rjson', '-e', 'puts JSON.generate(ARGV.map { |path| YAML.load_file(path) })', '.github/workflows/ci-elixir-verified.yml', '.github/workflows/ci-elixir.yml'], {encoding:'utf8'}));
const schema = (workflow.on||workflow.true).workflow_call.inputs;
const actualInputs = Object.fromEntries(Object.entries(schema).map(([k,v])=>[k,v.default]));
Object.assign(actualInputs, {'result-reuse-environment':'image@sha256:'+'c'.repeat(64)});
const producerRef = 'e0da/actions/.github/workflows/ci-elixir-verified.yml@'+'a'.repeat(40);
const steps = workflow.jobs.mix.steps;
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
function script(name) { return steps.find(s => s.name === name).with.script; }
const validProof = {key:'k', tree:'t', runtime:actualInputs['result-reuse-environment'], repository:'e0da/stack', workflow:'.github/workflows/mcog.yml', checkout:'merge', run_id:10, job_id:20};
async function verify({proof = {...validProof}, job = {run_id:10, name:'mcog / Mix', head_sha:'head', status:'completed', conclusion:'success', steps:['Run CI','Record native execution receipt','Attest native receipt as immutable artifact'].map(name=>({name,status:'completed',conclusion:'success'})), html_url:'proof-url'}, run = {head_sha:'head', path:'.github/workflows/mcog.yml', event:'pull_request', pull_requests:[{head:{sha:'head'},base:{sha:'base'}}]}, commit = {tree:{sha:'t'},parents:[{sha:'base'},{sha:'head'}]}, native = {...validProof}, artifacts, apiError, extraInputs = {}, caller = {jobs:{mcog:{uses:producerRef,with:actualInputs}}}} = {}) {
  const outputs = {};
  const core = {info:()=>{},setOutput:(k,v)=>outputs[k]=v, summary:{addRaw:()=>({write:async()=>{}})}};
  const fs = {readFileSync:()=>JSON.stringify(proof),writeFileSync:()=>{}};
  const github = {paginate:async()=>artifacts ?? [{id:30,name:'elixir-native-20-k',expired:false}],rest:{actions:{getJobForWorkflowRun:async()=>{if(apiError)throw Error(apiError);return {data:job};},getWorkflowRun:async()=>({data:run}),listWorkflowRunArtifacts(){},downloadArtifact:async()=>({data:Buffer.from('zip')})},git:{getCommit:async()=>({data:commit})},repos:{getContent:async()=>({data:{content:Buffer.from(JSON.stringify(workflow)).toString('base64')}})}}};
  await new AsyncFunction('require','process','core','github','context', script('Verify prior successful native job'))(
    name => name==='node:fs'?fs:{execFileSync:(program,args,options)=>program==='ruby'?options.input:program==='git'?JSON.stringify(caller):JSON.stringify(native)},
    {env:{PROOF_FILE:'receipt', PROOF_KEY:'k', PROOF_TREE:'t',PROOF_RUNTIME:validProof.runtime,PROOF_WORKFLOW:'.github/workflows/mcog.yml',PROOF_REVISION:'a'.repeat(40),PROOF_DEFAULTS:JSON.stringify(Object.fromEntries(Object.entries(schema).map(([k,v])=>[k,v.default]))),REUSE_INPUTS:JSON.stringify({...actualInputs,...extraInputs})}}, core, github,
    {repo:{owner:'e0da',repo:'stack'}});
  return outputs.reused;
}
test('successful prior native execution is reusable', async()=>assert.equal(await verify(),'true'));
for(const conclusion of ['failure','cancelled','skipped','timed_out',null]) test(`does not reuse ${conclusion} job`,async()=>assert.equal(await verify({job:{run_id:10,status:'completed',conclusion,steps:[]}}),'false'));
test('does not reuse unfinished job',async()=>assert.equal(await verify({job:{run_id:10,status:'in_progress',conclusion:null,steps:[]}}),'false'));
test('does not reuse a receipt from a different run',async()=>assert.equal(await verify({job:{run_id:11,status:'completed',conclusion:'success',steps:[]}}),'false'));
test('successful skipped-proof job cannot become native evidence',async()=>assert.equal(await verify({job:{run_id:10,status:'completed',conclusion:'success',steps:[{name:'Run CI',status:'completed',conclusion:'skipped'}]}}),'false'));
for(const [field,value] of [['key','wrong'],['tree','wrong'],['repository','other/repo']]) test(`rejects mismatched ${field}`,async()=>assert.equal(await verify({proof:{...validProof,[field]:value}}),'false'));
test('API errors cannot credit success',async()=>assert.rejects(()=>verify({apiError:'403'}),/403/));
test('only verified success bypasses setup and execution',()=>{
 for(const name of ['Identify immutable toolchain cache','Cache downloaded BEAM tools','Set up BEAM','Verify preinstalled BEAM','Cache Mix deps','Configure private git deps (SSH)','Install deps','Run CI']) assert.match(steps.find(s=>s.name===name).if,/steps.proof.outputs.reused != 'true'/,name);
 assert.match(steps.find(s=>s.id==='proof-key').if,/PRIVATE_DEPS_SSH_KEY == ''/);
 assert.equal((workflow.on||workflow.true).workflow_call.inputs['result-reuse-environment'].default,'');
 for(const name of ['Record native execution receipt','Save native execution receipt']) assert.match(steps.find(s=>s.name===name).if,/proof-cache.outputs.cache-hit != 'true'/);
});
const policy = {'beam-mode':'setup-beam','otp-version':'29.0.2','elixir-version':'1.20.1','result-reuse-environment':'ghcr.io/e0da/runner@sha256:'+'c'.repeat(64)};
async function identify(refs,tree='tree',platform='Linux-ARM64',inputs=JSON.stringify(policy), workflowPath='.github/workflows/mcog.yml', observedImage=JSON.parse(inputs)['result-reuse-environment']) {
 const out={};
 const fakeRequire=name=>name==='node:child_process'?{execFileSync:(_,args)=>args[0]==='show'?refs.map(ref=>`uses: e0da/actions/.github/workflows/ci-elixir-verified.yml@${ref}`).join('\n'):tree}:require(name);
 await new AsyncFunction('require','process','core',script('Identify tested tree and execution contract'))(fakeRequire,{env:{CALLER_WORKFLOW:`e0da/stack/${workflowPath}@refs/pull/1/merge`,REUSE_INPUTS:inputs,PROOF_PLATFORM:platform,E0DA_RUNNER_IMAGE_REF:observedImage}},{info:()=>{},setOutput:(k,v)=>out[k]=v});return out;
}
test('tree, platform, commands and reusable revision all invalidate proof',async()=>{
 const sha='a'.repeat(40),old=(await identify([sha])).key;
 for(const args of [[[sha],'other'],[[sha],'tree','Linux-X64'],[[sha],'tree','Linux-ARM64',JSON.stringify({...policy,'ci-command':'changed'})],[['b'.repeat(40)]]]) assert.notEqual((await identify(...args)).key,old);
});
for(const refs of [[],['main'],['a'.repeat(40),'b'.repeat(40)]]) test(`rejects ambiguous or mutable caller ${refs}`,async()=>assert.rejects(()=>identify(refs),/immutable/));

for(const change of [{'beam-mode':'runner-preinstalled'},{'otp-version':'29'},{'elixir-version':'1.20'},{'result-reuse-environment':'runner:latest'}]) test(`rejects unqualified environment ${JSON.stringify(change)}`,async()=>assert.rejects(()=>identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify({...policy,...change})),/exact downloaded/));
test('original native commands, cache paths and input defaults are preserved',()=>{
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
 const call=()=>new AsyncFunction('require','process','github','context','core',script('Record native execution receipt'))(()=>({writeFileSync:(_,s)=>saved=JSON.parse(s)}),{env:{GITHUB_RUN_ATTEMPT:'1',PROOF_RUNNER:'runner',PROOF_KEY:'k',PROOF_TREE:'t',PROOF_FILE:'receipt',PROOF_WORKFLOW:'.github/workflows/mcog.yml',PROOF_CHECKOUT:'merge',PROOF_RUNTIME:validProof.runtime}},{paginate:async()=>Array.from({length:count},(_,i)=>({id:i+20,status:'in_progress',runner_name:'runner'})),rest:{actions:{listJobsForWorkflowRunAttempt(){}}}},{repo:{owner:'e0da',repo:'stack'},runId:10},{setOutput:()=>{}});
 if(count===1) {await call();assert.deepEqual(saved,validProof);} else await assert.rejects(call,/uniquely/);
});

test('unrelated successful native job cannot authorize this tree/contract',async()=>{
 assert.equal(await verify({job:{run_id:10,head_sha:'unrelated-commit',workflow_name:'Unrelated workflow',name:'unrelated native checks',status:'completed',conclusion:'success',steps:[{name:'Run CI',status:'completed',conclusion:'success'}],html_url:'unrelated-job'}}),'false');
});

for(const change of [{commit:{tree:{sha:'other'},parents:[]}},{run:{head_sha:'head',path:'other.yml'}},{run:{head_sha:'other',path:'.github/workflows/mcog.yml'}},{commit:{tree:{sha:'t'},parents:[{sha:'other'},{sha:'head'}]}},{native:{...validProof,key:'forged'}},{native:{...validProof,job_id:99}},{artifacts:[]},{artifacts:[{id:30,name:'elixir-native-20-k',expired:true}]}]) test(`rejects wrong source/artifact ${JSON.stringify(change)}`,async()=>assert.equal(await verify(change),'false'));
test('push/dispatch proof binds exact run head',async()=>{
 assert.equal(await verify({proof:{...validProof,checkout:'head'},native:{...validProof,checkout:'head'},run:{head_sha:'head',path:'.github/workflows/mcog.yml',event:'workflow_dispatch'}}),'true');
 assert.equal(await verify({run:{head_sha:'head',path:'.github/workflows/mcog.yml',event:'workflow_dispatch'}}),'false');
});
test('artifact is immutable and precedes cache pointer publication',()=>{
 const artifact=steps.find(s=>s.name==='Attest native receipt as immutable artifact');
 assert.equal(artifact.with.overwrite,false);assert.equal(artifact.with['if-no-files-found'],'error');
 assert.ok(steps.indexOf(artifact)<steps.findIndex(s=>s.name==='Save native execution receipt'));
});

test('same-run unrelated job and separately uploaded matching artifact cannot attest execution contract',async()=>{
 assert.equal(await verify({job:{run_id:10,head_sha:'head',name:'unrelated command job',status:'completed',conclusion:'success',steps:[{name:'Run CI',status:'completed',conclusion:'success'}],html_url:'unrelated-job'}}),'false');
});

for (const call of [{uses:producerRef,with:{...actualInputs,'ci-command':'unrelated command'}},{uses:producerRef,with:{...actualInputs,'ci-command':'${{ inputs.command }}'}},{uses:'other/workflow@'+'a'.repeat(40),with:actualInputs},{uses:producerRef,with:actualInputs,strategy:{matrix:{part:[1,2]}}}]) test(`unbound producer executes native checks ${JSON.stringify(call)}`,async()=>assert.equal(await verify({caller:{jobs:{mcog:call}}}),'false'));
test('omitted caller inputs resolve from the pinned producer defaults',async()=>assert.equal(await verify({caller:{jobs:{mcog:{uses:producerRef,with:{'result-reuse-environment':actualInputs['result-reuse-environment']}}}}}),'true'));

test('an inline job cannot impersonate the native producer display name',async()=>assert.equal(await verify({caller:{jobs:{mcog:{uses:producerRef,with:actualInputs},other:{name:'mcog / Mix',steps:[]}}}}),'false'));
test('dynamic caller names cannot authorize proof',async()=>assert.equal(await verify({caller:{jobs:{mcog:{uses:producerRef,with:actualInputs},other:{name:'${{ inputs.name }}',steps:[]}}}}),'false'));

test('producer defaults binding stays identical to workflow input schema',()=>assert.deepEqual(JSON.parse(steps.find(s=>s.id==='proof').env.PROOF_DEFAULTS),Object.fromEntries(Object.entries(schema).map(([k,v])=>[k,v.default]))));

for(const name of ['Record native execution receipt','Attest native receipt as immutable artifact']) test(`skipped producer ${name} cannot attest native execution`,async()=>assert.equal(await verify({job:{run_id:10,head_sha:'head',name:'mcog / Mix',status:'completed',conclusion:'success',steps:['Run CI','Record native execution receipt','Attest native receipt as immutable artifact'].map(n=>({name:n,status:'completed',conclusion:n===name?'skipped':'success'}))}}),'false'));

test('dispatcher context extras do not change statically bound native inputs',async()=>assert.equal(await verify({extraInputs:{qualification:'native-proof'}}),'true'));

test('caller path changes invalidate proof identity',async()=>assert.notEqual((await identify(['a'.repeat(40)])).key,(await identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify(policy),'.github/workflows/other.yml')).key));
test('dispatcher context remains in proof identity',async()=>assert.notEqual((await identify(['a'.repeat(40)])).key,(await identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify({...policy,qualification:'other'}))).key));
test('caller cannot provide undeclared native inputs',async()=>assert.equal(await verify({extraInputs:{qualification:'native-proof'},caller:{jobs:{mcog:{uses:producerRef,with:{...actualInputs,qualification:'native-proof'}}}}}),'false'));

for(const observedImage of ['', 'image@sha256:'+'d'.repeat(64)]) test(`missing or mismatched provider image runs native (${observedImage})`,async()=>assert.equal((await identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify(policy),'.github/workflows/mcog.yml',observedImage)).key,undefined));

test('cached runtime ref must match the verified current runtime',async()=>assert.equal(await verify({proof:{...validProof,runtime:'other-image'}}),'false'));
test('immutable native artifact must attest runtime ref too',async()=>assert.equal(await verify({native:{...validProof,runtime:'other-image'}}),'false'));

const configuredRef='ghcr.io/e0da/actions-linux-runner:arc5@sha256:'+'c'.repeat(64);
test('exact tagged configured image ref is recorded in proof',async()=>assert.equal((await identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify({...policy,'result-reuse-environment':configuredRef}),'.github/workflows/mcog.yml',configuredRef)).runtime,configuredRef));
test('a different configured ref still runs native even with the same digest',async()=>assert.equal((await identify(['a'.repeat(40)],'tree','Linux-ARM64',JSON.stringify(policy),'.github/workflows/mcog.yml',configuredRef)).key,undefined));
