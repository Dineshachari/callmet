setInterval(() => {
  const botName = __MEETSCRIBE_BOT_NAME__;
  if (botName) {
    const nameField = Array.from(document.querySelectorAll('input, textarea')).find(element => {
      const label = `${element.getAttribute('aria-label') || ''} ${element.placeholder || ''} ${element.name || ''}`.toLowerCase();
      return label.includes('name');
    });

    if (nameField && !nameField.value) {
      nameField.value = botName;
      nameField.dispatchEvent(new Event('input', { bubbles: true }));
      nameField.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
  document.querySelector('[aria-label*="Turn off microphone"]')?.click();
  document.querySelector('[aria-label*="Turn off camera"]')?.click();
  const button = document.querySelector('[aria-label="Join now"],[aria-label="Ask to join"]');
  if (button) button.click();
}, 1000);
