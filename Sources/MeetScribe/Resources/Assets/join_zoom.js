setInterval(() => {
  document.querySelector('a[role="button"]')?.click();
  const nameInput = document.querySelector('#input-for-name');
  if (nameInput) {
    const botName = __MEETSCRIBE_BOT_NAME__;
    if (botName && !nameInput.value) {
      nameInput.value = botName;
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));
      nameInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
  document.querySelector('button.preview-join-button')?.click();
}, 1000);
