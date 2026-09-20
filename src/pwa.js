let installPrompt=null;
export const installed=()=>window.matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;window.dispatchEvent(new Event('myk2-install-ready'));});
window.addEventListener('appinstalled',()=>{installPrompt=null;window.dispatchEvent(new Event('myk2-install-ready'));});
export async function install(){if(!installPrompt)return false;await installPrompt.prompt();await installPrompt.userChoice;installPrompt=null;return true;}
export function registerPwa(){if('serviceWorker' in navigator&&import.meta.env.PROD)navigator.serviceWorker.register('./sw.js',{scope:'./'}).catch(()=>{});}
