(() => {
  'use strict';
  const {escapeHtml:e, name:displayName, copy, download} = window.GeneratorCore;
  const $ = id => document.getElementById(id);
  let serial = 0;
  const actionRules = [['alpha','Defeat Alpha Pal'],['predator','Defeat Predator Pal'],['tower','Defeat Tower Boss'],['raid','Complete Raid Boss battle'],['dungeon','Defeat dungeon Alpha / clear dungeon'],['new_pal','Capture a new Pal'],['capture_five','Capture 5 of one Pal species (once)'],['main_quest','Complete Main Quest'],['side_quest','Complete Side Quest']];
  const actionDefaults = () => ({'action_rewards.enabled':false,'action_rewards.announce':true,'action_rewards.worldboss_installed':true,...Object.fromEntries(actionRules.map(([id])=>[`action_rewards.${id}.credits`,'0']))});
  const defaults = () => ({...actionDefaults(),currency_name:'Credits',announce_currency_acquisition:true,transfers_enabled:true,starting_balance:'0',page_size:'6',allow_free_offers:false,currency_admin_uids:''});
  const offer = () => ({uid:++serial,id:`offer_${serial}`,enabled:false,name:'New offer',description:'',category:'supplies',max_purchases:'0',cooldown_seconds:'0',costs:[{kind:'currency',amount:'100',id:'',level:'0'}],rewards:[{kind:'item',id:'PalSphere',amount:'10',level:'0'}],extra:[]});
  const state = {settings:defaults(),offers:[],selected:null,extra:[],sections:'',filter:'',coreReminder:'600'};
  const selected = () => state.offers.find(o=>o.uid === state.selected);
  const button = (label, action, attr='') => `<button type="button" class="button button-secondary button-small" data-action="${action}" ${attr}>${label}</button>`;
  function field(label,key,value, type='text',attr='') {
    return `<label>${e(label)}<input type="${type}" data-key="${e(key)}" value="${e(value)}" ${attr}></label>`;
  }
  function flag(label,key,value) { return `<label>${e(label)}<select data-key="${key}"><option value="true"${value===true?' selected':''}>Yes</option><option value="false"${value!==true?' selected':''}>No</option></select></label>`; }
  function notice(text) { $('shop-validation').textContent = text; }
  function dirty() { $('shop-output').value=''; $('shop-download').disabled=true; notice('Changed. Generate to validate the current configuration.'); }
  function renderList() {
    const query=state.filter.toLowerCase().trim();
    const visible=state.offers.filter(o=>[o.id,o.name,o.category,...[...o.costs,...o.rewards].flatMap(r=>[r.id,displayName(r.kind==='pal'?'pals':'items',r.id)])].join(' ').toLowerCase().includes(query));
    $('shop-list').innerHTML=visible.map(o=>`<button type="button" class="button button-secondary shop-offer" data-offer="${o.uid}" aria-current="${o.uid===state.selected}">${e(o.name||o.id)}<small>${e(o.id)} · ${e(o.category)} · ${o.enabled?'enabled':'disabled'}</small></button>`).join('') || '<p class="shop-note">No matching offers.</p>';
  }
  function rows(o, section) {
    return `<section><h3>${section==='costs'?'Purchase costs':'Purchase rewards'}</h3>${o[section].map((r,i)=>{
      const kinds=section==='costs'?['currency','item','pal']:['currency','item','pal','title'];
      const custom=!kinds.includes(r.kind);
      return `<div class="shop-line" data-section="${section}" data-index="${i}"><label>Kind<select data-row="kind">${[...kinds,...(section==='rewards'?['custom']:[])].map(k=>`<option value="${k}"${(custom?'custom':r.kind)===k?' selected':''}>${k==='currency'?'Credits (shop currency)':k}</option>`).join('')}</select></label>
      ${custom?`<label>Registered provider kind<input data-row="customKind" value="${e(r.kind)}"></label>`:''}
      ${r.kind!=='currency'?`<label>${r.kind==='pal'?'Pal ID':r.kind==='item'?'Item ID':'Reward ID'}<input data-row="id" value="${e(r.id)}" list="${r.kind==='pal'?'pal-options':r.kind==='item'?'item-options':''}"></label>`:''}
      <label>Amount<input data-row="amount" type="number" min="1" max="1000000000" step="1" value="${e(r.amount)}"></label>
      ${r.kind==='pal'&&section==='rewards'?`<label>Pal level<input data-row="level" type="number" min="1" max="100" step="1" value="${e(r.level)}"></label>`:''}
      <div class="shop-controls">${button('Duplicate','duplicate-row')}${button('Remove','remove-row')}</div></div>`;
    }).join('')}<div class="shop-controls">${button(section==='costs'?'Add Cost':'Add Reward','add-row',`data-section="${section}"`)}</div></section>`;
  }
  function render() {
    renderList(); const o=selected(); $('shop-title').textContent=o?o.name||o.id:'Shop settings';
    if (!o) {
      $('shop-form').innerHTML=`<div class="shop-fields">${field('Currency display name','currency_name',state.settings.currency_name)}${field('Starting Credits','starting_balance',state.settings.starting_balance,'number','min="0" max="9000000000000" step="1"')}${field('Offers per chat page','page_size',state.settings.page_size,'number','min="1" max="10" step="1"')}${flag('Allow free offers','allow_free_offers',state.settings.allow_free_offers)}${flag('Announce acquired Credits','announce_currency_acquisition',state.settings.announce_currency_acquisition)}${flag('Allow Credit transfers','transfers_enabled',state.settings.transfers_enabled)}<label>Currency admin UIDs (one per line)<textarea data-key="currency_admin_uids">${e(state.settings.currency_admin_uids)}</textarea></label></div><p class="shop-note">Gold Coins use item ID Money; Dog Coins use DogCoin. Credits are the currency kind. Costs in Pals consume active-party Pals, not Palbox Pals.</p><section id="shop-action-rewards"><h3>Action rewards</h3><div class="shop-fields">${flag('Enable action rewards','action_rewards.enabled',state.settings['action_rewards.enabled'])}${flag('Announce action Credits','action_rewards.announce',state.settings['action_rewards.announce'])}${flag('WorldBossFramework installed','action_rewards.worldboss_installed',state.settings['action_rewards.worldboss_installed'])}${actionRules.map(([id,label])=>field(label+' — Credits',`action_rewards.${id}.credits`,state.settings[`action_rewards.${id}.credits`],'number','min="0" max="1000000000" step="1"')).join('')}</div><p class="shop-note">Requires the ServerShopFramework Action Rewards patch. Zero disables a reward. Wild Alpha and Predator kills exclude World Bosses through the matching WorldBossFramework patch. Tower and raid rewards follow native battle completion.</p><p class="shop-note">First captures are reconciled against server Paldex records. Five-capture rewards pay once per player and species when its server capture count reaches five; no Mimog/relic notification is required. Quests pay once per quest and player.</p><p class="shop-note">Dungeon clear means defeating the dungeon’s Alpha boss. It uses the dungeon rate instead of also paying the ordinary Alpha rate. World Boss purchase numbers are assigned by ServerShopFramework; use !shop worldboss to see them.</p></section><section><h3>Core reward reminders</h3><label>Reminder interval in seconds (0 disables)<input type="number" min="0" step="1" data-core-reminder value="${e(state.coreReminder)}"></label><div class="shop-controls">${button('Copy Core reminder setting','copy-core-reminder')}</div><p class="shop-note">Merge this setting into PixelsPalmodCore’s settings.config. It is separate from the Shop configuration. Reminders run on the minute clock.</p></section>`;
      return;
    }
    $('shop-form').innerHTML=`<div class="shop-controls">${button('Duplicate Offer','duplicate-offer')}${button('Remove Offer','remove-offer')}</div><div class="shop-fields">${field('Offer ID','id',o.id)}${flag('Enabled','enabled',o.enabled)}${field('Display name','name',o.name,'text','maxlength="80"')}${field('Category','category',o.category,'text','maxlength="48"')}${field('Description','description',o.description,'text','maxlength="300"')}${field('Purchase limit (0 = unlimited)','max_purchases',o.max_purchases,'number','min="0" max="1000000" step="1"')}${field('Purchase cooldown (seconds)','cooldown_seconds',o.cooldown_seconds,'number','min="0" max="31536000" step="1"')}</div>${rows(o,'costs')}${rows(o,'rewards')}<p class="shop-note">Title and custom rewards require their corresponding server provider. World Boss summons are contributed by WorldBossFramework; configure those on the World Boss page.</p>`;
  }
  function validate() {
    const errors=[], warnings=[]; const ids=new Set();
    const int=(v,min,max,path)=>{if(String(v).trim()===''||!Number.isSafeInteger(Number(v))||Number(v)<min||Number(v)>max)errors.push(`${path}: enter a whole number from ${min} to ${max}.`);};
    const text=(v,max,path)=>{if(/[\r\n\x00]/.test(String(v))||String(v).length>max)errors.push(`${path}: must be a single line of at most ${max} characters.`);};
    text(state.settings.currency_name,32,'Currency name');
    if(!state.settings.currency_name.trim())errors.push('Currency name is required.');
    int(state.settings.starting_balance,0,9000000000000,'Starting Credits'); int(state.settings.page_size,1,10,'Page size');
    for(const [id,label] of actionRules)int(state.settings[`action_rewards.${id}.credits`],0,1000000000,label+' Credits');
    for(const uid of state.settings.currency_admin_uids.split(/\s+/).filter(Boolean))if(!/^[a-fA-F0-9]{32}$/.test(uid)||/^\d+$/.test(uid))errors.push(`Admin UID ${uid} is invalid or numeric-only (Palladium would coerce it to a number); use permission grants for numeric-only UIDs`);
    for(const o of state.offers) {
      // Palladium's settings reader accepts only word/dot keys; numeric segments become array keys.
      if(!/^[A-Za-z_][A-Za-z0-9_]*$/.test(o.id))errors.push(`${o.id||'Offer'}: ID must start with a letter/underscore and contain only letters, digits or underscores.`);
      if(ids.has(o.id.toLowerCase()))errors.push(`Duplicate offer ID: ${o.id}`); ids.add(o.id.toLowerCase());
      if(o.id.toLowerCase().startsWith('worldboss_'))errors.push(`${o.id}: reserved for World Boss contributed offers; configure on the World Boss page.`);
      text(o.name,80,`${o.id} name`); text(o.description,300,`${o.id} description`);text(o.category,48,`${o.id} category`);
      int(o.max_purchases,0,1000000,`${o.id} limit`);int(o.cooldown_seconds,0,31536000,`${o.id} cooldown`);
      if(!o.rewards.length)errors.push(`${o.id}: at least one reward is required.`);
      if(!o.costs.length&&!state.settings.allow_free_offers)errors.push(`${o.id}: add a cost or allow free offers in Shop settings.`);
      for(const section of ['costs','rewards']) {
        if(o[section].length>128)errors.push(`${o.id}: at most 128 ${section} rows.`);
        o[section].forEach((r,i)=>{
          const path=`${o.id} ${section} ${i+1}`;
          if(!/^[a-z][a-z0-9_.-]*$/.test(r.kind))errors.push(`${path}: invalid provider kind.`);
          if(section==='costs'&&!['currency','item','pal'].includes(r.kind))errors.push(`${path}: unsupported cost kind.`);
          if(r.kind==='worldboss_summon')errors.push(`${path}: use the World Boss page for summon offers.`);
          int(r.amount,1,1000000000,path+' amount');
          text(r.id,128,path+' ID');
          if(r.kind!=='currency'&&!String(r.id).trim())errors.push(`${path}: ID is required.`);
          int(r.level??(r.kind==='pal'?1:0),r.kind==='pal'?1:0,r.kind==='pal'?100:1000,path+' level');
          if(['item','pal'].includes(r.kind)&&!(window.GeneratorCore.data[r.kind==='pal'?'pals':'items']||[]).some(x=>x.id===r.id))warnings.push(`${path}: ${r.id} is not in the shared reference database; verify this custom ID on your server.`);
          if(!['currency','item','pal'].includes(r.kind))warnings.push(`${path}: the ${r.kind} provider must be installed and accept this reward ID.`);
        });
      }
    }
    if(state.extra.length||state.offers.some(o=>o.extra.length)||state.sections)warnings.push('Imported additional settings and permission sections were preserved verbatim. Review them in the output.');
    return {errors,warnings};
  }
  function generate() {
    const {errors,warnings}=validate();
    if(errors.length){$('shop-output').value='';$('shop-download').disabled=true;notice('Not generated:\n'+errors.join('\n'));return null;}
    // No quoting or inline comments: the installed Palladium parser retains them as literal text.
    const lines=['; ServerShopFramework v1.0.0 settings — generated by Palworld Config Generator'];
    const put=(k,v)=>lines.push(`${k} = ${String(v).trim()}`);
    for(const k of ['currency_name','starting_balance','page_size','allow_free_offers','announce_currency_acquisition','transfers_enabled'])put(k,state.settings[k]);
    state.settings.currency_admin_uids.split(/\s+/).filter(Boolean).forEach((v,i)=>put(`currency_admin_uids.${i+1}`,v.toUpperCase()));
    for(const k of Object.keys(actionDefaults()))put(k,state.settings[k]);
    lines.push(...state.extra);
    // Explicitly override default offers even when the list is intentionally empty.
    if(!state.offers.length)put('offers','');
    for(const o of state.offers){
      lines.push(''); const base=`offers.${o.id}.`;
      for(const k of ['enabled','name','description','category','max_purchases','cooldown_seconds'])put(base+k,o[k]);
      for(const section of ['costs','rewards'])o[section].forEach((r,i)=>{
        const prefix=base+section+'.'+(i+1)+'.';put(prefix+'kind',r.kind);
        if(r.kind!=='currency')put(prefix+'id',r.id);put(prefix+'amount',r.amount);
        if(r.kind==='pal'||Number(r.level)!==0)put(prefix+'level',r.level);
        for(const [k,v] of r.extra||[])put(prefix+k,v);
      });
      for(const [k,v] of o.extra)put(base+k,v);
    }
    if(state.sections)lines.push('',state.sections);
    const result=lines.join('\n')+'\n';$('shop-output').value=result;$('shop-download').disabled=false;
    notice(`Valid: ${state.offers.length} offers.\n`+warnings.join('\n'));return result;
  }
  function importText(text) {
    const settings=defaults(), offers=new Map(), extra=[], admin=[],seen=new Set(); let sections='',sectionStarted=false;
    const known=new Set(['enabled','name','description','category','max_purchases','cooldown_seconds']);
    String(text).replace(/^\uFEFF/,'').split(/\r?\n/).forEach((raw,i)=>{
      const line=raw.trim(); if(sectionStarted||line.startsWith('[')){sectionStarted=true;sections+=raw+'\n';return;}
      if(!line||/^[;#]/.test(line))return;
      const m=/^([A-Za-z0-9_.]+)\s*=\s*(.*)$/.exec(line);if(!m)throw Error(`Line ${i+1}: invalid settings assignment.`);
      const [,key,v]=m;if(seen.has(key))throw Error(`Line ${i+1}: duplicate key ${key}.`);for(const prior of seen)if(key.startsWith(prior+'.')||prior.startsWith(key+'.'))throw Error(`Line ${i+1}: conflicting scalar and nested settings: ${prior}, ${key}.`);seen.add(key);
      if(Object.hasOwn(settings,key)&&key!=='currency_admin_uids'){
        if(typeof settings[key]==='boolean'){if(!['true','false'].includes(v))throw Error(`${key}: true or false required.`);settings[key]=v==='true';}else settings[key]=v;return;
      }
      const am=/^currency_admin_uids\.([1-9]\d*)$/.exec(key);if(am){admin.push([Number(am[1]),v]);return;}
      if(key==='offers'&&v==='')return;
      if(key.startsWith('spawners.'))throw Error('This is a World Boss config; load it on the World Boss page.');
      const om=/^offers\.([^.]+)\.(.+)$/.exec(key);
      if(!om){if(key.startsWith('offers')||key.startsWith('currency_admin_uids'))throw Error(`Unsupported structured setting: ${key}`);extra.push(raw);return;}
      const [,id,path]=om;
      if(!offers.has(id)){const o=offer();Object.assign(o,{id,enabled:true,name:id,description:'',category:'general',costs:[],rewards:[],rawRows:{costs:new Map(),rewards:new Map()}});offers.set(id,o);}
      const o=offers.get(id);
      if(known.has(path)){if(path==='enabled'){if(!['true','false'].includes(v))throw Error(`${key}: true or false required.`);o[path]=v==='true';}else o[path]=v;return;}
      const rm=/^(costs|rewards)\.([1-9]\d*)\.([A-Za-z0-9_]+)$/.exec(path);
      if(!rm){if(/^(costs|rewards)(\.|$)/.test(path))throw Error(`Invalid reward/cost path: ${key}`);o.extra.push([path,v]);return;}
      const [,section,index,k]=rm;if(Number(index)>128)throw Error(`${key}: row index exceeds 128.`);
      if(!o.rawRows[section].has(Number(index)))o.rawRows[section].set(Number(index),Object.create(null));o.rawRows[section].get(Number(index))[k]=v;
    });
    for(const o of offers.values())for(const section of ['costs','rewards']){
      o[section]=[...o.rawRows[section]].sort((a,b)=>a[0]-b[0]).map(([,r])=>({kind:(r.kind||(section==='costs'?'currency':'item')).trim().toLowerCase(),id:r.id??r.item??r.species??r.title??'',amount:r.amount??r.count??'1',level:r.level??((r.kind||'').trim().toLowerCase()==='pal'?'1':'0'),extra:Object.entries(r).filter(([k])=>!['kind','id','item','species','title','amount','count','level'].includes(k))}));
    }
    settings.currency_admin_uids=admin.sort((a,b)=>a[0]-b[0]).map(x=>x[1]).join('\n');
    state.settings=settings;state.offers=[...offers.values()];state.extra=extra;state.sections=sections.trimEnd();state.selected=null;state.filter='';$('shop-search').value='';dirty();render();notice('Loaded settings.config. Review settings, offers and preserved permission sections, then Generate.');
  }
  $('shop-form').addEventListener('submit',ev=>ev.preventDefault());
  $('shop-form').addEventListener('input',ev=>{
    const el=ev.target,o=selected(),row=el.closest('[data-index]');
    if(el.hasAttribute('data-core-reminder')){state.coreReminder=el.value;return;}
    if(el.dataset.row&&row&&o){const r=o[row.dataset.section][Number(row.dataset.index)];r[el.dataset.row==='customKind'?'kind':el.dataset.row]=el.value==='custom'?'custom_provider':el.value;if(el.dataset.row==='kind')r.level=r.kind==='pal'?'1':'0';}
    else if(el.dataset.key){const target=o||state.settings;target[el.dataset.key]=['enabled','allow_free_offers','announce_currency_acquisition','transfers_enabled','action_rewards.enabled','action_rewards.announce','action_rewards.worldboss_installed'].includes(el.dataset.key)?el.value==='true':el.value;}
    else return;dirty();renderList();
  });
  $('shop-form').addEventListener('change',ev=>{if(ev.target.dataset.row==='kind')render();});
  $('shop-form').addEventListener('click',async ev=>{
    const b=ev.target.closest('[data-action]'),o=selected();if(!b)return;
    if(b.dataset.action==='copy-core-reminder'){
      const n=Number(state.coreReminder);
      if(state.coreReminder.trim()===''||!Number.isSafeInteger(n)||n<0){notice('Enter a nonnegative whole reminder interval.');return;}
      const line=`pending_reward_reminder_seconds = ${n}\n`;
      try{notice(await copy(line)?'Core reminder setting copied. Merge into PixelsPalmodCore settings.config.':line);}catch(_){notice(line);}return;
    }
    if(!o)return;
    const row=b.closest('[data-index]');const section=b.dataset.section||row?.dataset.section;const index=Number(row?.dataset.index);
    switch(b.dataset.action){
      case 'duplicate-offer':{const clone=JSON.parse(JSON.stringify(o));clone.uid=++serial;let id=o.id+'_copy';let n=2;while(state.offers.some(x=>x.id.toLowerCase()===id.toLowerCase()))id=o.id+'_copy_'+n++;clone.id=id;state.offers.splice(state.offers.indexOf(o)+1,0,clone);state.selected=clone.uid;break;}
      case 'remove-offer':state.offers=state.offers.filter(x=>x!==o);state.selected=null;break;
      case 'add-row':if(o[section].length<128)o[section].push({kind:section==='costs'?'currency':'item',id:'',amount:'1',level:'0'});break;
      case 'duplicate-row':if(o[section].length<128)o[section].splice(index+1,0,JSON.parse(JSON.stringify(o[section][index])));break;
      case 'remove-row':o[section].splice(index,1);break;
    }dirty();render();
  });
  $('shop-list').addEventListener('click',ev=>{const b=ev.target.closest('[data-offer]');if(b){state.selected=Number(b.dataset.offer);render();}});
  const actionButton=document.createElement('button');
  actionButton.type='button';actionButton.className=$('shop-settings').className;
  actionButton.id='shop-action-settings';actionButton.textContent='Action Rewards';
  $('shop-settings').insertAdjacentElement('afterend',actionButton);
  actionButton.onclick=()=>{state.selected=null;render();$('shop-action-rewards').scrollIntoView({block:'start'});};
  $('shop-settings').onclick=()=>{state.selected=null;render();};
  $('shop-add').onclick=()=>{const o=offer();while(state.offers.some(x=>x.id===o.id))o.id=`offer_${++serial}`;state.offers.push(o);state.selected=o.uid;dirty();render();};
  $('shop-search').oninput=ev=>{state.filter=ev.target.value;renderList();};
  for(const id of ['shop-generate','shop-generate-top'])$(id).onclick=generate;
  for(const id of ['shop-copy','shop-copy-top'])$(id).onclick=async()=>{const text=generate();if(text)try{notice(await copy(text)?'Configuration copied.':'Clipboard unavailable. Select and copy the output text.');}catch(_){notice('Clipboard unavailable. Select and copy the output text.');}};
  $('shop-download').onclick=()=>{const text=generate();if(text)download('settings.config',text);};
  $('shop-load').onclick=()=>$('shop-file').click();
  $('shop-file').onchange=async ev=>{const file=ev.target.files[0];if(!file)return;try{if(file.size>2*1024*1024)throw Error('Config exceeds 2 MB.');importText(await file.text());}catch(error){notice('Not loaded: '+error.message);}finally{ev.target.value='';}};
  render();
})();
