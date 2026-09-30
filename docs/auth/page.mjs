import {readLink, passwordError, createAuth} from './core.mjs';
import {publicKey} from './config.mjs';
const link = readLink(location.hash.slice(1));
history.replaceState(null, '', location.pathname);
const element = id => document.getElementById(id);
const message = text => {element('message').textContent = text;};
const auth = createAuth(publicKey);
let token = null;
let busy = false;
if (link) {
  element('title').textContent = link.type === 'recovery' ? 'Reset your password' : 'Confirm your email';
  message('Choose where you would like to continue.');
  element('actions').hidden = false;
  if (link.native && /iPhone|iPad|Android/i.test(navigator.userAgent)) {
    element('native').hidden = false;
    element('native').href = link.native;
  }
}
element('browser').addEventListener('click', async () => {
  if (busy || !link) return;
  busy = true;
  element('browser').disabled = true;
  element('native').hidden = true;
  message('Checking your link...');
  try {
    const data = await auth.verify(link);
    if (!data.access_token) throw new Error('Missing session');
    token = data.access_token;
    element('actions').hidden = true;
    if (link.type === 'recovery') {
      element('password-form').hidden = false;
      message('Choose a new password for your EvenPlate account.');
      element('password').focus();
    } else {
      message('Your email is confirmed. Open EvenPlate and sign in on your phone.');
      await auth.logout(token);
      token = null;
    }
  } catch (_) {
    message('This link could not be verified. If you already confirmed it, try signing in. Otherwise, request a new email from EvenPlate.');
  } finally { busy = false; }
});
element('password-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (busy || !token) return;
  const password = element('password').value;
  const error = passwordError(password, element('confirmation').value);
  if (error) {message(error); return;}
  busy = true;
  element('save').disabled = true;
  message('Saving your password...');
  try {
    await auth.update(password, token);
    element('password-form').reset();
    element('password-form').hidden = true;
    message('Your password is saved. Open EvenPlate and sign in with your new password.');
    await auth.logout(token);
    token = null;
  } catch (error) {
    message(error.code === 'same_password' ? 'Choose a password different from your current password.' :
      'The update could not be confirmed. Your password may have changed. Try signing in with your new password before requesting another reset email.');
  } finally {busy = false; element('save').disabled = false;}
});
