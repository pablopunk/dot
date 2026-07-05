export function fuzzyMatch(query: string, candidates: string[]): string[] {
  if (!query) return [...candidates];
  if (candidates.length === 0) return [];

  const lower = query.toLowerCase();
  const allMatches = new Set<string>();

  const exact = candidates.filter((c) => c.toLowerCase() === lower);
  for (const c of exact) allMatches.add(c);

  const substring = candidates.filter((c) => c.toLowerCase().includes(lower));
  for (const c of substring) allMatches.add(c);

  const charMatch = candidates.filter((c) => {
    let idx = 0;
    const clower = c.toLowerCase();
    for (let i = 0; i < lower.length; i++) {
      idx = clower.indexOf(lower[i], idx);
      if (idx === -1) return false;
      idx++;
    }
    return true;
  });
  for (const c of charMatch) allMatches.add(c);

  const result = [...allMatches];

  return result.sort((a, b) => {
    const aLower = a.toLowerCase();
    const bLower = b.toLowerCase();

    if (aLower === lower && bLower !== lower) return -1;
    if (bLower === lower && aLower !== lower) return 1;

    const aSubIdx = aLower.indexOf(lower);
    const bSubIdx = bLower.indexOf(lower);

    if (aSubIdx !== -1 && bSubIdx === -1) return -1;
    if (bSubIdx !== -1 && aSubIdx === -1) return 1;

    if (aSubIdx !== -1 && bSubIdx !== -1) {
      if (aSubIdx !== bSubIdx) return aSubIdx - bSubIdx;
      return a.length - b.length;
    }

    const aScore = charOrderScore(aLower, lower);
    const bScore = charOrderScore(bLower, lower);
    if (bScore !== aScore) return bScore - aScore;
    return a.length - b.length;
  });
}

function charOrderScore(candidate: string, query: string): number {
  let score = 0;
  let idx = 0;
  for (let i = 0; i < query.length; i++) {
    const found = candidate.indexOf(query[i], idx);
    if (found === -1) break;
    score += found === idx ? 2 : 1;
    idx = found + 1;
  }
  return score;
}

export function resolveComponentNames(
  queries: string[],
  available: string[]
): { found: string[]; missing: string[] } {
  if (queries.length === 0) return { found: [], missing: [] };

  const foundSet = new Set<string>();
  const missing: string[] = [];

  for (const q of queries) {
    const matches = fuzzyMatch(q, available);
    if (matches.length === 0) {
      missing.push(q);
    } else {
      for (const m of matches) foundSet.add(m);
    }
  }

  return { found: [...foundSet], missing };
}
