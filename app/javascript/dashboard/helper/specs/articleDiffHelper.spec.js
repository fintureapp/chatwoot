import {
  renderInlineDiff,
  buildDiffBlocks,
  hasPendingChanges,
} from '../articleDiffHelper';

describe('articleDiffHelper', () => {
  describe('renderInlineDiff', () => {
    it('returns the text unchanged when there is no difference', () => {
      const result = renderInlineDiff('hello world', 'hello world');
      expect(result).toBe('hello world');
      expect(result).not.toContain('<ins');
      expect(result).not.toContain('<del');
    });

    it('wraps inserted words in <ins>', () => {
      const result = renderInlineDiff('hello', 'hello there');
      expect(result).toContain('hello');
      expect(result).toContain('<ins');
      expect(result).toContain('there');
    });

    it('wraps removed words in <del>', () => {
      const result = renderInlineDiff('hello there', 'hello');
      expect(result).toContain('<del');
      expect(result).toContain('there');
    });

    it('keeps a single removal contiguous when a word repeats', () => {
      const result = renderInlineDiff(
        'How to use Agent bots?',
        'How How to Agent bots?'
      );
      expect(result).toBe(
        'How <ins class="!bg-n-teal-5 !text-n-teal-12 !no-underline rounded px-0.5">How</ins> to <del class="!bg-n-ruby-5 !text-n-ruby-12 !line-through rounded px-0.5">use</del> Agent bots?'
      );
    });

    it('escapes markup when diffing plain text', () => {
      const result = renderInlineDiff('a', 'a <b>');
      expect(result).toContain('&lt;b&gt;');
      expect(result).not.toContain('<b>');
    });

    it('treats a cleared empty string as a full deletion', () => {
      const result = renderInlineDiff('gone', '');
      expect(result).toContain('<del');
      expect(result).toContain('gone');
    });
  });

  describe('buildDiffBlocks', () => {
    it('passes an unchanged block through as equal', () => {
      const blocks = buildDiffBlocks('same para', 'same para');
      expect(blocks).toEqual([{ type: 'equal', md: 'same para' }]);
    });

    it('marks an appended block as added', () => {
      const blocks = buildDiffBlocks('a', 'a\n\nb');
      expect(blocks).toContainEqual({ type: 'equal', md: 'a' });
      expect(blocks).toContainEqual({ type: 'added', md: 'b' });
    });

    it('marks a deleted block as removed', () => {
      const blocks = buildDiffBlocks('a\n\nb', 'a');
      expect(blocks).toContainEqual({ type: 'removed', md: 'b' });
    });

    it('emits the old block then the new block for a reworded section', () => {
      const blocks = buildDiffBlocks('hello world', 'hello there');
      expect(blocks).toEqual([
        { type: 'removed', md: 'hello world' },
        { type: 'added', md: 'hello there' },
      ]);
    });
  });

  describe('hasPendingChanges', () => {
    it('is true when a draft title or content is staged', () => {
      expect(hasPendingChanges({ draftContent: 'edit' })).toBe(true);
      expect(hasPendingChanges({ draftTitle: 'edit' })).toBe(true);
    });

    it('treats a cleared empty-string draft as a pending change', () => {
      expect(hasPendingChanges({ draftTitle: '' })).toBe(true);
    });

    it('is false with no draft columns', () => {
      expect(hasPendingChanges({ title: 'live' })).toBe(false);
      expect(hasPendingChanges({})).toBe(false);
      expect(hasPendingChanges(null)).toBe(false);
    });
  });
});
