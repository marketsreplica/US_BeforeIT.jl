import assert from "node:assert/strict";
import test from "node:test";

import { relationshipTableCaption } from "./table.js";

test("comparison table copy does not promise a hidden export", () => {
  const caption = relationshipTableCaption(12, 0, 12, { comparison: true });
  assert.match(caption, /returned comparison deltas only/);
  assert.match(caption, /comparison export is not available/);
  assert.doesNotMatch(caption, /Export includes every server-matching relationship/);
});
