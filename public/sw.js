const CACHE='myk2-shell-v1.3.0';
const ROOT=new URL('./',self.location).href;
self.addEventListener('install',event=>{event.waitUntil((async()=>{const cache=await caches.open(CACHE);const response=await fetch(ROOT,{cache:'reload'});if(!response.ok)throw Error('App shell unavailable');await cache.put(ROOT,response.clone());const html=await response.text();const assets=[...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(m=>new URL(m[1],ROOT)).filter(url=>url.origin===self.location.origin&&url.pathname.includes('/assets/')).map(url=>url.href);await cache.addAll([...new Set([...assets,ROOT+'manifest.webmanifest',ROOT+'icons/icon-192.png',ROOT+'icons/icon-512.png'])]);})());});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('myk2-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{const request=event.request,url=new URL(request.url);if(request.method!=='GET'||url.origin!==self.location.origin||!url.href.startsWith(ROOT))return;
 if(request.mode==='navigate'){event.respondWith(fetch(request).then(response=>{if(response.ok){const copy=response.clone();event.waitUntil(caches.open(CACHE).then(cache=>cache.put(ROOT,copy)));}return response;}).catch(async()=>await caches.match(ROOT)||Response.error()));return;}
 if(/\/(assets|icons)\//.test(url.pathname)){event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{if(response.ok){const copy=response.clone();event.waitUntil(caches.open(CACHE).then(cache=>cache.put(request,copy)));}return response;})));}
});

