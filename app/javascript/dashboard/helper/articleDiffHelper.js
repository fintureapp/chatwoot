// Powers the "unpublished changes" preview: marks what changed between the live
// article and the draft — word by word in the title, block by block in the body.

const INS_CLASS = '!bg-n-teal-5 !text-n-teal-12 !no-underline rounded px-0.5';
const DEL_CLASS = '!bg-n-ruby-5 !text-n-ruby-12 !line-through rounded px-0.5';

// Detailed compare gets slow on huge texts; past this, show all old as removed
// and all new as added.
const MAX_DIFF_TOKENS = 2000;

const tokenizeWords = value => (value || '').match(/\S+/g) || [];

const escapeHtml = value =>
  value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Compares two lists in order and reports what's the same (`equal`), removed
// (`del`) or added (`ins`), keeping as much unchanged as possible. `keyOf` says
// how to compare items (title passes words, body passes blocks).
const diffSequence = (a, b, keyOf = item => item) => {
  const n = a.length;
  const m = b.length;
  if (n > MAX_DIFF_TOKENS || m > MAX_DIFF_TOKENS) {
    return [
      ...a.map(item => ({ type: 'del', item })),
      ...b.map(item => ({ type: 'ins', item })),
    ];
  }

  const dp = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i -= 1) {
    for (let j = m - 1; j >= 0; j -= 1) {
      dp[i][j] =
        keyOf(a[i]) === keyOf(b[j])
          ? dp[i + 1][j + 1] + 1
          : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  const ops = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (keyOf(a[i]) === keyOf(b[j])) {
      ops.push({ type: 'equal', item: a[i] });
      i += 1;
      j += 1;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.push({ type: 'del', item: a[i] });
      i += 1;
    } else {
      ops.push({ type: 'ins', item: b[j] });
      j += 1;
    }
  }
  while (i < n) {
    ops.push({ type: 'del', item: a[i] });
    i += 1;
  }
  while (j < m) {
    ops.push({ type: 'ins', item: b[j] });
    j += 1;
  }
  return ops;
};

const wrapDiff = {
  ins: text => `<ins class="${INS_CLASS}">${text}</ins>`,
  del: text => `<del class="${DEL_CLASS}">${text}</del>`,
};

// Builds the highlighted title. Compares whole words (not single spaces) so
// repeated words/spaces don't make the highlights jump around, then rejoins
// with single spaces — a run of added/removed words shares one <ins>/<del> tag.
export const renderInlineDiff = (oldValue, newValue) => {
  const ops = diffSequence(tokenizeWords(oldValue), tokenizeWords(newValue));

  const segments = [];
  let run = [];
  let runType = null;
  const flushRun = () => {
    if (!run.length) return;
    const text = run.map(escapeHtml).join(' ');
    segments.push(wrapDiff[runType] ? wrapDiff[runType](text) : text);
    run = [];
  };

  ops.forEach(({ type, item }) => {
    if (type !== runType) flushRun();
    runType = type;
    run.push(item);
  });
  flushRun();

  return segments.join(' ');
};

// Split on blank lines so each paragraph, heading or list compares as one piece.
const splitBlocks = text =>
  (text || '')
    .split(/\n\s*\n/)
    .map(block => block.trim())
    .filter(Boolean);

const normalize = text => text.replace(/\s+/g, ' ').trim();

const BLOCK_TYPE = { equal: 'equal', del: 'removed', ins: 'added' };

// Compares the body block by block; an edited paragraph shows as old-removed
// then new-added. `key` ignores spacing so whitespace-only changes still match.
export const buildDiffBlocks = (oldText, newText) => {
  const toBlocks = text =>
    splitBlocks(text).map(md => ({ md, key: normalize(md) }));
  const ops = diffSequence(toBlocks(oldText), toBlocks(newText), b => b.key);
  return ops.map(op => ({ type: BLOCK_TYPE[op.type], md: op.item.md }));
};

export const hasPendingChanges = article =>
  article?.draftTitle != null || article?.draftContent != null;
