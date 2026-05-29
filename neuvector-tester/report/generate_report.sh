#!/usr/bin/env bash
# report/generate_report.sh — generuje raport HTML z pliku results.json
set -euo pipefail

RESULTS_FILE="${1:-/report/results.json}"
OUTPUT_FILE="${2:-/report/report.html}"

if [[ ! -f "${RESULTS_FILE}" ]]; then
  echo "Błąd: Brak pliku wyników: ${RESULTS_FILE}" >&2
  exit 1
fi

# Odczyt danych z JSON
SUITE=$(jq -r '.suite' "${RESULTS_FILE}")
STARTED=$(jq -r '.started_at' "${RESULTS_FILE}")
FINISHED=$(jq -r '.finished_at // "N/A"' "${RESULTS_FILE}")
NS=$(jq -r '.cluster_namespace' "${RESULTS_FILE}")
TOTAL=$(jq -r '.summary.total // 0' "${RESULTS_FILE}")
PASSED=$(jq -r '.summary.passed // 0' "${RESULTS_FILE}")
BLOCKED=$(jq -r '.summary.blocked // 0' "${RESULTS_FILE}")
FAILED=$(jq -r '.summary.failed // 0' "${RESULTS_FILE}")
TIMEOUT=$(jq -r '.summary.timed_out // 0' "${RESULTS_FILE}")

# Generuj wiersze tabeli testów
ROWS=""
while IFS= read -r test; do
  NAME=$(echo "${test}" | jq -r '.name')
  MODULE=$(echo "${test}" | jq -r '.module')
  STATUS=$(echo "${test}" | jq -r '.status')
  DESC=$(echo "${test}" | jq -r '.description')
  DETAILS=$(echo "${test}" | jq -r '.details // ""' | head -c 200)
  TS=$(echo "${test}" | jq -r '.timestamp')

  case "${STATUS}" in
    PASS)    BADGE='<span class="badge pass">PASS</span>' ;;
    BLOCKED) BADGE='<span class="badge blocked">BLOCKED</span>' ;;
    FAIL)    BADGE='<span class="badge fail">FAIL</span>' ;;
    TIMEOUT) BADGE='<span class="badge timeout">TIMEOUT</span>' ;;
    *)       BADGE="<span class=\"badge\">${STATUS}</span>" ;;
  esac

  DETAILS_HTML=""
  if [[ -n "${DETAILS}" ]]; then
    DETAILS_HTML="<details><summary>Szczegóły</summary><pre>${DETAILS}</pre></details>"
  fi

  ROWS+="<tr>
    <td class='module-col'>${MODULE}</td>
    <td>${NAME}</td>
    <td>${BADGE}</td>
    <td>${DESC}${DETAILS_HTML}</td>
    <td class='ts-col'>${TS}</td>
  </tr>"
done < <(jq -c '.tests[]' "${RESULTS_FILE}")

# Oblicz procenty dla wykresu
if [[ ${TOTAL} -gt 0 ]]; then
  PCT_PASS=$(echo "scale=1; ${PASSED} * 100 / ${TOTAL}" | bc)
  PCT_BLOCKED=$(echo "scale=1; ${BLOCKED} * 100 / ${TOTAL}" | bc)
  PCT_FAIL=$(echo "scale=1; ${FAILED} * 100 / ${TOTAL}" | bc)
  PCT_TIMEOUT=$(echo "scale=1; ${TIMEOUT} * 100 / ${TOTAL}" | bc)
else
  PCT_PASS=0; PCT_BLOCKED=0; PCT_FAIL=0; PCT_TIMEOUT=0
fi

cat > "${OUTPUT_FILE}" <<HTMLEOF
<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NeuVector Security Test Report</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@300;400;600;700&display=swap');

  :root {
    --bg: #0a0e1a;
    --surface: #111827;
    --surface2: #1c2333;
    --border: #2a3347;
    --text: #e2e8f0;
    --text-dim: #64748b;
    --accent: #3b82f6;
    --pass: #22c55e;
    --blocked: #f59e0b;
    --fail: #ef4444;
    --timeout: #a855f7;
    --pass-bg: rgba(34,197,94,0.12);
    --blocked-bg: rgba(245,158,11,0.12);
    --fail-bg: rgba(239,68,68,0.12);
    --timeout-bg: rgba(168,85,247,0.12);
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: 'IBM Plex Sans', sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
    line-height: 1.6;
  }

  /* ── Header ── */
  header {
    background: linear-gradient(135deg, #0f172a 0%, #1e3a5f 50%, #0f172a 100%);
    border-bottom: 1px solid var(--border);
    padding: 2.5rem 2rem 2rem;
    position: relative;
    overflow: hidden;
  }
  header::before {
    content: '';
    position: absolute;
    inset: 0;
    background: repeating-linear-gradient(
      -45deg,
      transparent,
      transparent 40px,
      rgba(59,130,246,0.03) 40px,
      rgba(59,130,246,0.03) 41px
    );
  }
  .header-inner { position: relative; max-width: 1200px; margin: 0 auto; }
  .logo-row { display: flex; align-items: center; gap: 1rem; margin-bottom: 0.75rem; }
  .shield-icon {
    width: 48px; height: 48px;
    background: linear-gradient(135deg, var(--accent), #60a5fa);
    border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    font-size: 1.5rem;
    box-shadow: 0 0 30px rgba(59,130,246,0.4);
    flex-shrink: 0;
  }
  h1 { font-size: 1.75rem; font-weight: 700; letter-spacing: -0.5px; }
  h1 span { color: var(--accent); }
  .subtitle { font-size: 0.85rem; color: var(--text-dim); font-family: 'IBM Plex Mono', monospace; margin-top: 0.25rem; }
  .meta-grid {
    display: flex; gap: 2.5rem; margin-top: 1.25rem; flex-wrap: wrap;
  }
  .meta-item label { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 1px; color: var(--text-dim); display: block; }
  .meta-item span { font-family: 'IBM Plex Mono', monospace; font-size: 0.85rem; color: var(--text); }

  /* ── Layout ── */
  main { max-width: 1200px; margin: 0 auto; padding: 2rem; }

  /* ── Summary Cards ── */
  .summary-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 1rem;
    margin-bottom: 2rem;
  }
  .stat-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.25rem 1.5rem;
    text-align: center;
    position: relative;
    overflow: hidden;
    transition: transform 0.2s;
  }
  .stat-card:hover { transform: translateY(-2px); }
  .stat-card::before {
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0;
    height: 3px;
  }
  .stat-card.total::before  { background: var(--accent); }
  .stat-card.pass::before   { background: var(--pass); }
  .stat-card.blocked::before{ background: var(--blocked); }
  .stat-card.fail::before   { background: var(--fail); }
  .stat-card.timeout::before{ background: var(--timeout); }
  .stat-num {
    font-size: 2.5rem; font-weight: 700; font-family: 'IBM Plex Mono', monospace;
    line-height: 1;
  }
  .stat-card.total  .stat-num { color: var(--accent); }
  .stat-card.pass   .stat-num { color: var(--pass); }
  .stat-card.blocked .stat-num { color: var(--blocked); }
  .stat-card.fail   .stat-num { color: var(--fail); }
  .stat-card.timeout .stat-num { color: var(--timeout); }
  .stat-label {
    font-size: 0.75rem; text-transform: uppercase; letter-spacing: 1px;
    color: var(--text-dim); margin-top: 0.5rem;
  }
  .stat-pct {
    font-size: 0.75rem; color: var(--text-dim);
    font-family: 'IBM Plex Mono', monospace;
  }

  /* ── Progress bar ── */
  .progress-section {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 2rem;
  }
  .progress-section h2 {
    font-size: 0.9rem; text-transform: uppercase;
    letter-spacing: 1px; color: var(--text-dim); margin-bottom: 1rem;
  }
  .progress-bar {
    height: 28px; border-radius: 6px;
    background: var(--surface2);
    overflow: hidden; display: flex;
  }
  .pb-pass    { background: var(--pass);    }
  .pb-blocked { background: var(--blocked); }
  .pb-fail    { background: var(--fail);    }
  .pb-timeout { background: var(--timeout); }
  .progress-legend {
    display: flex; gap: 1.5rem; margin-top: 0.75rem; flex-wrap: wrap;
  }
  .legend-item { display: flex; align-items: center; gap: 0.4rem; font-size: 0.8rem; }
  .legend-dot { width: 10px; height: 10px; border-radius: 2px; }

  /* ── Table ── */
  .table-section {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    overflow: hidden;
  }
  .table-header {
    padding: 1.25rem 1.5rem;
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
  }
  .table-header h2 { font-size: 1rem; font-weight: 600; }
  .filter-row { display: flex; gap: 0.5rem; flex-wrap: wrap; }
  .filter-btn {
    border: 1px solid var(--border);
    background: var(--surface2);
    color: var(--text-dim);
    padding: 0.3rem 0.8rem;
    border-radius: 20px;
    font-size: 0.75rem;
    cursor: pointer;
    font-family: 'IBM Plex Sans', sans-serif;
    transition: all 0.2s;
  }
  .filter-btn:hover, .filter-btn.active { border-color: var(--accent); color: var(--accent); background: rgba(59,130,246,0.1); }

  .table-wrap { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th {
    text-align: left; padding: 0.75rem 1rem;
    font-size: 0.7rem; text-transform: uppercase;
    letter-spacing: 1px; color: var(--text-dim);
    background: var(--surface2);
    border-bottom: 1px solid var(--border);
    white-space: nowrap;
  }
  td { padding: 0.875rem 1rem; border-bottom: 1px solid rgba(255,255,255,0.04); vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: rgba(255,255,255,0.02); }

  .module-col { font-family: 'IBM Plex Mono', monospace; font-size: 0.75rem; color: var(--text-dim); white-space: nowrap; }
  .ts-col { font-family: 'IBM Plex Mono', monospace; font-size: 0.7rem; color: var(--text-dim); white-space: nowrap; }

  /* ── Badges ── */
  .badge {
    display: inline-block; padding: 0.2rem 0.6rem;
    border-radius: 20px; font-size: 0.7rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.5px;
    white-space: nowrap;
    font-family: 'IBM Plex Mono', monospace;
  }
  .badge.pass    { background: var(--pass-bg);    color: var(--pass);    border: 1px solid rgba(34,197,94,0.3); }
  .badge.blocked { background: var(--blocked-bg); color: var(--blocked); border: 1px solid rgba(245,158,11,0.3); }
  .badge.fail    { background: var(--fail-bg);    color: var(--fail);    border: 1px solid rgba(239,68,68,0.3); }
  .badge.timeout { background: var(--timeout-bg); color: var(--timeout); border: 1px solid rgba(168,85,247,0.3); }

  details summary {
    cursor: pointer; font-size: 0.75rem; color: var(--text-dim);
    margin-top: 0.4rem; user-select: none;
  }
  details pre {
    background: var(--surface2); border: 1px solid var(--border);
    border-radius: 6px; padding: 0.75rem; margin-top: 0.5rem;
    font-size: 0.7rem; font-family: 'IBM Plex Mono', monospace;
    color: var(--text-dim); overflow-x: auto; white-space: pre-wrap;
    word-break: break-all; max-height: 150px; overflow-y: auto;
  }

  /* ── Footer ── */
  footer {
    text-align: center; padding: 2rem;
    font-size: 0.75rem; color: var(--text-dim);
    border-top: 1px solid var(--border); margin-top: 2rem;
    font-family: 'IBM Plex Mono', monospace;
  }

  @media print {
    body { background: white; color: black; }
    header { background: #1e3a5f; }
    .filter-row { display: none; }
    details[open] pre { max-height: none; }
  }
</style>
</head>
<body>

<header>
  <div class="header-inner">
    <div class="logo-row">
      <div class="shield-icon">🛡</div>
      <div>
        <h1>NeuVector <span>Security</span> Test Report</h1>
        <div class="subtitle">RKE2 Kubernetes Cluster · Namespace: ${NS}</div>
      </div>
    </div>
    <div class="meta-grid">
      <div class="meta-item"><label>Start</label><span>${STARTED}</span></div>
      <div class="meta-item"><label>Koniec</label><span>${FINISHED}</span></div>
      <div class="meta-item"><label>Namespace</label><span>${NS}</span></div>
      <div class="meta-item"><label>Tryb NeuVector</label><span>Protect</span></div>
    </div>
  </div>
</header>

<main>

  <!-- Summary Cards -->
  <div class="summary-grid">
    <div class="stat-card total">
      <div class="stat-num">${TOTAL}</div>
      <div class="stat-label">Łącznie testów</div>
    </div>
    <div class="stat-card pass">
      <div class="stat-num">${PASSED}</div>
      <div class="stat-label">Nie zablokowane</div>
      <div class="stat-pct">${PCT_PASS}%</div>
    </div>
    <div class="stat-card blocked">
      <div class="stat-num">${BLOCKED}</div>
      <div class="stat-label">Zablokowane</div>
      <div class="stat-pct">${PCT_BLOCKED}%</div>
    </div>
    <div class="stat-card fail">
      <div class="stat-num">${FAILED}</div>
      <div class="stat-label">Błąd testu</div>
      <div class="stat-pct">${PCT_FAIL}%</div>
    </div>
    <div class="stat-card timeout">
      <div class="stat-num">${TIMEOUT}</div>
      <div class="stat-label">Timeout</div>
      <div class="stat-pct">${PCT_TIMEOUT}%</div>
    </div>
  </div>

  <!-- Progress bar -->
  <div class="progress-section">
    <h2>Rozkład wyników</h2>
    <div class="progress-bar">
      <div class="pb-pass"    style="width:${PCT_PASS}%"    title="PASS: ${PASSED}"></div>
      <div class="pb-blocked" style="width:${PCT_BLOCKED}%" title="BLOCKED: ${BLOCKED}"></div>
      <div class="pb-fail"    style="width:${PCT_FAIL}%"    title="FAIL: ${FAILED}"></div>
      <div class="pb-timeout" style="width:${PCT_TIMEOUT}%" title="TIMEOUT: ${TIMEOUT}"></div>
    </div>
    <div class="progress-legend">
      <div class="legend-item"><div class="legend-dot" style="background:var(--pass)"></div> PASS — atak nie zablokowany / test pozytywny</div>
      <div class="legend-item"><div class="legend-dot" style="background:var(--blocked)"></div> BLOCKED — NeuVector zablokował atak</div>
      <div class="legend-item"><div class="legend-dot" style="background:var(--fail)"></div> FAIL — błąd środowiskowy testu</div>
      <div class="legend-item"><div class="legend-dot" style="background:var(--timeout)"></div> TIMEOUT — przekroczono limit czasu</div>
    </div>
  </div>

  <!-- Tests Table -->
  <div class="table-section">
    <div class="table-header">
      <h2>Wyniki testów</h2>
      <div class="filter-row">
        <button class="filter-btn active" onclick="filterTable('ALL')">Wszystkie</button>
        <button class="filter-btn" onclick="filterTable('PASS')">PASS</button>
        <button class="filter-btn" onclick="filterTable('BLOCKED')">BLOCKED</button>
        <button class="filter-btn" onclick="filterTable('FAIL')">FAIL</button>
        <button class="filter-btn" onclick="filterTable('TIMEOUT')">TIMEOUT</button>
      </div>
    </div>
    <div class="table-wrap">
      <table id="results-table">
        <thead>
          <tr>
            <th>Moduł</th>
            <th>Test</th>
            <th>Status</th>
            <th>Opis</th>
            <th>Czas</th>
          </tr>
        </thead>
        <tbody>
          ${ROWS}
        </tbody>
      </table>
    </div>
  </div>

</main>

<footer>
  Wygenerowano: $(date -u +"%Y-%m-%d %H:%M:%S UTC") · NeuVector Security Test Suite · RKE2
</footer>

<script>
function filterTable(status) {
  const rows = document.querySelectorAll('#results-table tbody tr');
  rows.forEach(row => {
    const badge = row.querySelector('.badge');
    if (!badge) return;
    row.style.display = (status === 'ALL' || badge.classList.contains(status.toLowerCase()))
      ? '' : 'none';
  });
  document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.classList.toggle('active', btn.textContent.trim() === status);
  });
}
</script>

</body>
</html>
HTMLEOF

echo "Raport HTML wygenerowany: ${OUTPUT_FILE}"
