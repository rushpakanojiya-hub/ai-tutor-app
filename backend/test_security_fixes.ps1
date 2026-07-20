# test_security_fixes.ps1
# Run from anywhere. Fill in EMAIL/PASSWORD for an existing student account below,
# or pass them as parameters: .\test_security_fixes.ps1 -Email "you@x.com" -Password "..."

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$Email = "REPLACE_WITH_TEST_EMAIL",
    [string]$Password = "REPLACE_WITH_TEST_PASSWORD"
)

function Pass($msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Info($msg) { Write-Host $msg -ForegroundColor Cyan }

# --- Login ---
Info "`n=== Logging in ==="
try {
    $loginBody = @{ email = $Email; password = $Password } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json"
    $token = $login.token
    if (-not $token) { Fail "No token in login response - check email/password"; exit 1 }
    Pass "Logged in as $($login.user.name)"
} catch {
    Fail "Login request failed: $($_.Exception.Message)"
    exit 1
}
$headers = @{ Authorization = "Bearer $token" }

# =========================================================================
# TEST 1: /api/quiz/generate must return quiz_session_id and must NOT
# leak the answer key (correct_option/correct_options/correct_text/
# explanation) in the questions it sends back.
# =========================================================================
Info "`n=== TEST 1: Quiz generate - session id present, answer key stripped ==="
$genBody = @{ topic = "Photosynthesis"; num_questions = 3; question_types = @("single_mcq") } | ConvertTo-Json
$gen = Invoke-RestMethod -Uri "$BaseUrl/api/quiz/generate" -Method Post -Body $genBody -ContentType "application/json" -Headers $headers

$sessionId = $gen.data.quiz_session_id
if ($sessionId) { Pass "quiz_session_id present: $sessionId" } else { Fail "quiz_session_id MISSING from response" }

$leaked = $false
foreach ($q in $gen.data.questions) {
    if ($null -ne $q.correct_option -or $null -ne $q.correct_options -or $q.correct_text -or $q.explanation) {
        $leaked = $true
    }
}
if ($leaked) { Fail "Answer key (correct_option/correct_options/correct_text/explanation) IS present in /generate response - vulnerability still open!" }
else { Pass "No answer-key fields present in /generate response" }

# =========================================================================
# TEST 2: Tampering attempt. We deliberately submit a WRONG answer while
# ALSO lying in the request body's own correct_option field (pretending
# our wrong answer is correct). Before the fix, the server would have
# trusted our lie and marked it correct. After the fix, it must grade
# against its own stored key regardless of what we claim.
# =========================================================================
Info "`n=== TEST 2: Tampering - client lies about the answer key ==="
$questions = $gen.data.questions
$answeredQuestions = @()
foreach ($q in $questions) {
    $answeredQuestions += @{
        question_type   = $q.question_type
        selected_option  = 99          # almost certainly wrong
        correct_option   = 99          # LIE: claim 99 is correct, matching our selection
        selected_options = @()
        submitted_text   = "lied answer"
    }
}
$attemptBody = @{
    quiz_session_id    = $sessionId
    topic              = "Photosynthesis"
    time_taken_seconds = 10
    questions          = $answeredQuestions
} | ConvertTo-Json -Depth 5

$attempt = Invoke-RestMethod -Uri "$BaseUrl/api/quiz/freeform/attempt" -Method Post -Body $attemptBody -ContentType "application/json" -Headers $headers
$score = $attempt.data.score_percent
if ($score -eq 0) {
    Pass "Score is 0% despite client lying about correct_option=99 - server ignored the client's fake answer key"
} else {
    Fail "Score is $score% - server may still be trusting client-supplied correct_option! (expected 0%)"
}

# =========================================================================
# TEST 3: Missing quiz_session_id must be rejected (can't grade without
# the server-held key).
# =========================================================================
Info "`n=== TEST 3: Missing quiz_session_id must be rejected ==="
try {
    $badBody = @{ topic = "Photosynthesis"; questions = $answeredQuestions } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$BaseUrl/api/quiz/freeform/attempt" -Method Post -Body $badBody -ContentType "application/json" -Headers $headers -ErrorAction Stop
    Fail "Request without quiz_session_id was ACCEPTED (should have been rejected with 400)"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) { Pass "Request without quiz_session_id correctly rejected (400)" }
    else { Fail "Unexpected status: $($_.Exception.Response.StatusCode.value__)" }
}

# =========================================================================
# TEST 4: Session is single-use - resubmitting the SAME session_id
# (already consumed by TEST 2) must now be rejected.
# =========================================================================
Info "`n=== TEST 4: Session should be single-use ==="
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/quiz/freeform/attempt" -Method Post -Body $attemptBody -ContentType "application/json" -Headers $headers -ErrorAction Stop
    Fail "Resubmitting the same quiz_session_id was ACCEPTED (expected 400 - session already consumed)"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) { Pass "Resubmitting the same session correctly rejected (400) - single-use confirmed" }
    else { Fail "Unexpected status: $($_.Exception.Response.StatusCode.value__)" }
}

# =========================================================================
# TEST 5: YouTube endpoint error responses must never include a "details"
# key (that was the leak vector). We can't force a real upstream failure
# without breaking your live API key, so this just checks the error SHAPE
# on a request we know will fail validation.
# =========================================================================
Info "`n=== TEST 5: YouTube error response shape (no 'details' key) ==="
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/videos/search?q=" -Method Get -Headers $headers -ErrorAction Stop
    Fail "Empty q was accepted (expected 400)"
} catch {
    $body = $_.ErrorDetails.Message | ConvertFrom-Json
    if ($body.details) { Fail "Response STILL includes a 'details' key: $($body.details)" }
    else { Pass "Error response has no 'details' key" }
}

Info "`n=== Manual check (optional, higher confidence) ==="
Info "To directly confirm the API-key leak is closed, temporarily set an invalid"
Info "YOUTUBE_API_KEY in .env, restart the backend, then call:"
Info "  Invoke-RestMethod -Uri `"$BaseUrl/api/videos/search?q=test`" -Headers `$headers"
Info "The error response should say only 'search failed' - no key, no URL, anywhere in it."
Info "Revert .env and restart the backend afterwards."
