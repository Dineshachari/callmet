(() => {
  const botName = __MEETSCRIBE_BOT_NAME__;
  const startedAt = Date.now();
  let finished = false;
  const state = {
    status: 'starting',
    lastAction: '',
    askToJoinClicked: false,
    joined: false,
    denied: false,
    hint: '',
    title: '',
    url: '',
    bodyProbe: '',
    elapsedMs: 0
  };

  function normalize(value) {
    return (value || '').toString().replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function isVisible(el) {
    if (!el) return false;
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.visibility !== 'hidden' && style.display !== 'none' && rect.width > 0 && rect.height > 0;
  }

  function setNameIfNeeded() {
    if (!botName) return false;
    function setNativeValue(input, value) {
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
      if (setter) {
        setter.call(input, value);
      } else {
        input.value = value;
      }
    }

    const selectors = [
      'input#c18[jsname="YPqjbf"]',
      'input[jsname="YPqjbf"]',
      'input#c18',
      'input[aria-label="Your name"]',
      'input[aria-label*="name" i]',
      'input[placeholder*="name" i]',
      'input[type="text"]',
      'textarea[aria-label*="name" i]'
    ];
    for (const selector of selectors) {
      const field = document.querySelector(selector);
      if (!field || !isVisible(field)) continue;
      const current = normalize(field.value);
      if (current === normalize(botName)) return false;
      field.focus();
      setNativeValue(field, botName);
      field.dispatchEvent(new Event('input', { bubbles: true }));
      field.dispatchEvent(new Event('change', { bubbles: true }));
      state.lastAction = `set-name:${selector}`;
      return true;
    }
    return false;
  }

  function tokenize(text) {
    return normalize(text).split(/[^a-z0-9]+/g).filter(Boolean);
  }

  function fuzzyScore(label, pattern) {
    const a = normalize(label);
    const b = normalize(pattern);
    if (!a || !b) return 0;
    if (a === b) return 1;
    if (a.includes(b)) return 0.95;
    if (b.includes(a)) return 0.75;

    const aTokens = tokenize(a);
    const bTokens = tokenize(b);
    if (!aTokens.length || !bTokens.length) return 0;

    let overlap = 0;
    for (const token of bTokens) {
      if (aTokens.includes(token)) overlap += 1;
    }
    const tokenRatio = overlap / bTokens.length;

    // Reward labels that keep the same leading intent words.
    const firstWordBoost = aTokens[0] && bTokens[0] && aTokens[0] === bTokens[0] ? 0.1 : 0;
    return Math.min(1, tokenRatio + firstWordBoost);
  }

  function clickBestMatchingAction(actionName, patterns, minScore = 0.66) {
    const candidates = Array.from(
      document.querySelectorAll('button, [role="button"], [jsaction], [tabindex]')
    );
    let best = null;
    let bestLabel = '';
    let bestScore = 0;

    for (const el of candidates) {
      if (!isVisible(el)) continue;
      if (el.hasAttribute('disabled') || el.getAttribute('aria-disabled') === 'true') continue;
      const label = normalize(
        el.getAttribute('aria-label') ||
        el.getAttribute('data-tooltip') ||
        el.textContent
      );
      if (!label) continue;

      let score = 0;
      for (const pattern of patterns) {
        score = Math.max(score, fuzzyScore(label, pattern));
      }
      if (score > bestScore) {
        best = el;
        bestLabel = label;
        bestScore = score;
      }
    }

    if (best && bestScore >= minScore) {
      best.click();
      state.lastAction = `clicked:${actionName}:${bestLabel}:${bestScore.toFixed(2)}`;
      return true;
    }
    return false;
  }

  function clickFirstMatchingButton(textPatterns) {
    return clickBestMatchingAction('generic', textPatterns, 0.62);
  }

  function clickMeetIntroFlowButton() {
    const introImage = document.querySelector('img[src*="permissions_flow_intro"], img[src*="permissions_flow_intro_v2"]');
    if (!introImage) return false;

    // Explicit handling for Meet's onboarding span:
    // <span ...>Continue without microphone and camera</span>
    const spanCandidates = Array.from(document.querySelectorAll('span, div'));
    for (const node of spanCandidates) {
      const text = normalize(node.textContent);
      if (!text.includes('continue without microphone and camera')) continue;
      const clickable = node.closest('button,[role="button"],[jsaction],[tabindex]');
      if (clickable && isVisible(clickable)) {
        clickable.click();
        state.lastAction = 'clicked:continue-without-mic-cam';
        return true;
      }
      if (isVisible(node)) {
        node.click();
        state.lastAction = 'clicked:continue-without-mic-cam-span';
        return true;
      }
    }

    // Google Meet intro/onboarding pages can block pre-join controls.
    const clicked = clickFirstMatchingButton([
      'continue',
      'next',
      'got it',
      'ok',
      'i understand',
      'allow',
      'allow access'
    ]);

    if (clicked) {
      state.lastAction = 'clicked:meet-intro';
    }
    return clicked;
  }

  function clickSignInPromptGotIt() {
    const bodyText = normalize(document.body?.innerText || '');
    if (!bodyText.includes('sign in with your google account')) return false;

    const gotItNodes = Array.from(document.querySelectorAll('button, [role="button"], span, div'));
    for (const node of gotItNodes) {
      const text = normalize(node.textContent);
      if (text !== 'got it') continue;
      const clickable = node.closest('button,[role="button"],[jsaction],[tabindex]');
      if (clickable && isVisible(clickable)) {
        clickable.click();
        state.lastAction = 'clicked:sign-in-got-it';
        return true;
      }
      if (isVisible(node)) {
        node.click();
        state.lastAction = 'clicked:sign-in-got-it-node';
        return true;
      }
    }
    return false;
  }

  function clickAskToJoinSpan() {
    const spans = Array.from(document.querySelectorAll('span[jsname="V67aGc"].UywwFc-vQzf8d, span[jsname="V67aGc"]'));
    for (const span of spans) {
      const text = normalize(span.textContent);
      if (text !== 'ask to join') continue;
      const clickable = span.closest('button,[role="button"],[jsaction],[tabindex]');
      if (clickable && isVisible(clickable)) {
        clickable.click();
        state.askToJoinClicked = true;
        state.lastAction = 'clicked:ask-to-join-span';
        return true;
      }
      if (isVisible(span)) {
        span.click();
        state.askToJoinClicked = true;
        state.lastAction = 'clicked:ask-to-join-span-node';
        return true;
      }
    }
    return false;
  }

  function turnOffDevices() {
    clickBestMatchingAction('turn-off-mic', ['turn off microphone', 'microphone off', 'mute microphone'], 0.62);
    clickBestMatchingAction('turn-off-camera', ['turn off camera', 'camera off', 'disable camera'], 0.62);
  }

  function inCallNow() {
    const bodyText = normalize(document.body?.innerText || '');
    if (
      bodyText.includes('you have joined') ||
      bodyText.includes('leave call') ||
      bodyText.includes('end call') ||
      bodyText.includes("you're the only one here")
    ) {
      return true;
    }
    return !!document.querySelector(
      'button[aria-label*="leave call" i],button[aria-label*="end call" i],button[data-tooltip*="Leave call" i],button[data-tooltip*="End call" i]'
    );
  }

  function isLobbyWaitingNow() {
    const bodyText = normalize(document.body?.innerText || '');
    return (
      bodyText.includes('asking to join') ||
      bodyText.includes('ask to join') ||
      bodyText.includes('someone in the call will let you in') ||
      bodyText.includes('waiting for someone to let you in')
    );
  }

  function isDeniedNow() {
    const bodyText = normalize(document.body?.innerText || '');
    return (
      bodyText.includes('you can\'t join this call') ||
      bodyText.includes('you can\'t join this video call') ||
      bodyText.includes('cannot join this meeting') ||
      bodyText.includes('you were removed from the meeting') ||
      bodyText.includes('meeting code is invalid')
    );
  }

  function detectHint() {
    const bodyText = normalize(document.body?.innerText || '');
    if (bodyText.includes('sign in') || bodyText.includes('choose an account')) {
      return 'auth-required';
    }
    if (bodyText.includes('this browser is not supported') || bodyText.includes('update your browser')) {
      return 'browser-gate';
    }
    if (bodyText.includes('meeting code is invalid') || bodyText.includes('can\'t find the meeting')) {
      return 'invalid-link';
    }
    if (isLobbyWaitingNow()) {
      return 'waiting-for-host';
    }
    return '';
  }

  function tick() {
    if (finished) return;
    state.elapsedMs = Date.now() - startedAt;
    state.title = document.title || '';
    state.url = location.href || '';
    state.bodyProbe = normalize((document.body?.innerText || '').slice(0, 180));
    state.hint = detectHint();
    if (inCallNow()) {
      state.status = 'joined';
      state.joined = true;
      finished = true;
      return;
    }
    if (isDeniedNow()) {
      state.status = 'denied';
      state.denied = true;
      finished = true;
      return;
    }

    state.status = isLobbyWaitingNow() || state.askToJoinClicked ? 'waiting' : 'joining';
    if (state.hint === 'auth-required') {
      // Do not terminate early; these pages often require a "Got it" click first.
      state.status = 'auth-required';
    } else if (state.hint === 'browser-gate' || state.hint === 'invalid-link') {
      state.status = state.hint;
      finished = true;
      return;
    }
    clickMeetIntroFlowButton();
    clickSignInPromptGotIt();
    setNameIfNeeded();
    clickAskToJoinSpan();
    clickBestMatchingAction('sign-in', ['sign in', 'use another account', 'choose an account'], 0.72);
    // Some Meet flows require this gate before join controls show up.
    clickFirstMatchingButton(['continue without microphone and camera', 'continue without mic']);
    turnOffDevices();

    const clickedJoin = clickBestMatchingAction('join', [
      'join now',
      'ask to join',
      'request to join',
      'join meeting',
      'join'
    ], 0.60);
    if (clickedJoin) {
      const bodyText = normalize(document.body?.innerText || '');
      if (bodyText.includes('ask to join') || bodyText.includes('asking to join')) {
        state.askToJoinClicked = true;
      }
    }

    // Stop retrying after 2 minutes to avoid infinite clicking on hard failure pages.
    if (Date.now() - startedAt > 120000) {
      if (!state.joined && !state.denied) {
        state.status = state.askToJoinClicked ? 'timeout-waiting' : 'timeout';
      }
      finished = true;
    }
  }

  window.__MEETSCRIBE_GET_MEET_STATE = () => ({ ...state });
  setInterval(tick, 900);
})();
