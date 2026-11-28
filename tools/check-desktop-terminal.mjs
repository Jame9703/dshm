import assert from 'node:assert/strict';
import { loadTerminalEmulator } from '../entry/src/main/ets/desktop/terminal/TerminalEmulator.js';

const pauseUntilWritten = (terminal, input) => new Promise(resolve => terminal.write(input, resolve));

async function check(create) {
  const replies = [];
  const terminal = create(32, 4, 24, reply => replies.push(reply));
  try {
    await pauseUntilWritten(terminal, 'old row\r\n\x1b[2');
    await pauseUntilWritten(terminal, ';1H\x1b[38;2;18;52;86m窗口\x1b[0m');
    let screen = terminal.frame();
    assert.equal(screen.rows[1][0].text, '窗');
    assert.equal(screen.rows[1][0].cells, 2, 'wide characters occupy two cells');
    assert.equal(screen.rows[1][0].foreground, '#123456');
    assert.equal(screen.rows[1][1].column, 2);
    assert.equal(screen.cursorColumn, 4);
    assert.equal(screen.cursorRow, 1);

    await pauseUntilWritten(terminal, '\x1b[?25l\x1b[6n');
    assert.equal(terminal.frame().cursorVisible, false);
    assert.deepEqual(replies, ['\x1b[2;5R'], 'screen-position response is relayed');
    assert.equal(terminal.paste('a\r\nb\nc'), 'a\rb\rc');
    await pauseUntilWritten(terminal, '\x1b[?25h\x1b[?1h\x1b[?2004h');
    assert.equal(terminal.frame().cursorVisible, true);
    assert.equal(terminal.isApplicationCursor(), true);
    assert.equal(terminal.paste('a\nb'), '\x1b[200~a\rb\x1b[201~');

    await pauseUntilWritten(terminal, '\x1b[?1049hALT');
    assert.match(terminal.visibleText(), /ALT/);
    assert.doesNotMatch(terminal.visibleText(), /old row/);
    await pauseUntilWritten(terminal, '\x1b[?1049l');
    assert.match(terminal.visibleText(), /old row/);
    assert.match(terminal.visibleText(), /窗口/);

    terminal.resize(24, 3);
    await pauseUntilWritten(terminal, '\x1b[3;1H\r\nthird\r\nfourth\r\nfifth');
    assert.match(terminal.visibleText(), /fifth/);
    terminal.scroll(-3);
    screen = terminal.frame();
    assert.equal(screen.cursorVisible, false);
    assert.doesNotMatch(terminal.visibleText(), /fifth/);
  } finally {
    terminal.dispose();
  }
}

async function checkFocus(create) {
  const reports = [];
  const terminal = create(32, 4, 24, reply => reports.push(reply));
  try {
    terminal.setFocused(true);
    assert.deepEqual(reports, [], 'focus is silent before the program enables reporting');
    await pauseUntilWritten(terminal, '\x1b[?1004h\x1b[?1004h');
    terminal.setFocused(true);
    terminal.setFocused(false);
    terminal.setFocused(false);
    await pauseUntilWritten(terminal, '\x1b[?1004l');
    terminal.setFocused(true);
    assert.deepEqual(reports, ['\x1b[I', '\x1b[I', '\x1b[O'], 'query replies and real focus changes are distinct');
  } finally {
    terminal.dispose();
  }
}

const create = await loadTerminalEmulator();
await check(create);
await checkFocus(create);
if (process.argv.includes('--self-test')) {
  const dropsEscapeSequence = (...args) => {
    const terminal = create(...args);
    const write = terminal.write.bind(terminal);
    terminal.write = (input, done) => write(input.replaceAll('\x1b', ''), done);
    return terminal;
  };
  await assert.rejects(check(dropsEscapeSequence), { name: 'AssertionError' });
  const ignoresFocusChanges = (...args) => {
    const terminal = create(...args);
    terminal.setFocused = () => {};
    return terminal;
  };
  await assert.rejects(checkFocus(ignoresFocusChanges), { name: 'AssertionError' });
}
console.log('PASS native terminal screen, ANSI chunks, cursor and focus reports, alternate buffer, paste and scrollback');
