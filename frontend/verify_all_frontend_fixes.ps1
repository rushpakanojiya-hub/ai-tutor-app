# verify_all_frontend_fixes.ps1
# Run from your FRONTEND project root (e.g. C:\Users\ABC\Desktop\ai_tutor_app\frontend)
# Checks that every delivered frontend fix is actually present on disk.

$root = Get-Location
Write-Host "Verifying all frontend fixes in $root" -ForegroundColor Cyan
Write-Host ""
$pass = 0
$fail = 0

$path = Join-Path $root "lib/models/quiz_attempt_model.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'GeneratedQuiz' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/models/quiz_attempt_model.dart -> Naya wrapper class jo quiz_session_id carry karta hai" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/models/quiz_attempt_model.dart -> MISSING: Naya wrapper class jo quiz_session_id carry karta hai" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/models/quiz_attempt_model.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/services/quiz_service.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'required String quizSessionId' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/services/quiz_service.dart -> submitFreeformAttempt ab session id maangta hai" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/services/quiz_service.dart -> MISSING: submitFreeformAttempt ab session id maangta hai" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/services/quiz_service.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/lessons/quiz_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern '_gradedAnswers' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/lessons/quiz_screen.dart -> Results ab server ke response se aate hain, client-side answer-key se nahi" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/lessons/quiz_screen.dart -> MISSING: Results ab server ke response se aate hain, client-side answer-key se nahi" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/lessons/quiz_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/core/routes/app_router.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'quizSessionId' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/core/routes/app_router.dart -> Route session id ko QuizScreen tak pass karta hai" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/core/routes/app_router.dart -> MISSING: Route session id ko QuizScreen tak pass karta hai" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/core/routes/app_router.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/quiz/ai_quiz_generator_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'generated.quizSessionId' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/quiz/ai_quiz_generator_screen.dart -> Generator session id ko route tak bhejta hai" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/quiz/ai_quiz_generator_screen.dart -> MISSING: Generator session id ko route tak bhejta hai" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/quiz/ai_quiz_generator_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/live_class_room_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'BUG FIX (critical)' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/live_class_room_screen.dart -> Double navigation-pop bug fix (Leave/End Class)" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/live_class_room_screen.dart -> MISSING: Double navigation-pop bug fix (Leave/End Class)" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/live_class_room_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/courses/lesson_management_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'controller leak' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/courses/lesson_management_screen.dart -> Video preview controller leak fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/courses/lesson_management_screen.dart -> MISSING: Video preview controller leak fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/courses/lesson_management_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/courses/lesson_form_dialog.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'if (!mounted) return' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/courses/lesson_form_dialog.dart -> Async gap ke baad mounted checks" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/courses/lesson_form_dialog.dart -> MISSING: Async gap ke baad mounted checks" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/courses/lesson_form_dialog.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/student_live_classes_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern '_shortTime' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/student_live_classes_screen.dart -> Unguarded substring(0,5) crash-risk fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/student_live_classes_screen.dart -> MISSING: Unguarded substring(0,5) crash-risk fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/student_live_classes_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/models/live_class_model.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'shortStartTime' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/models/live_class_model.dart -> Shared safe time-display getters" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/models/live_class_model.dart -> MISSING: Shared safe time-display getters" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/models/live_class_model.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/admin_live_classes_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'shortStartTime' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/admin_live_classes_screen.dart -> Unguarded substring fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/admin_live_classes_screen.dart -> MISSING: Unguarded substring fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/admin_live_classes_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/my_live_classes_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'shortStartTime' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/my_live_classes_screen.dart -> Unguarded substring fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/my_live_classes_screen.dart -> MISSING: Unguarded substring fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/my_live_classes_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/waiting_room_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'shortStartTime' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/waiting_room_screen.dart -> Unguarded substring fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/waiting_room_screen.dart -> MISSING: Unguarded substring fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/waiting_room_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/lessons/lesson_player_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'controller leak' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/lessons/lesson_player_screen.dart -> Video controller leak fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/lessons/lesson_player_screen.dart -> MISSING: Video controller leak fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/lessons/lesson_player_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/resource_video_viewer_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'controller leak' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/resource_video_viewer_screen.dart -> Video controller leak fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/resource_video_viewer_screen.dart -> MISSING: Video controller leak fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/resource_video_viewer_screen.dart" -ForegroundColor Red
  $fail++
}

$path = Join-Path $root "lib/screens/liveclass/create_live_class_screen.dart"
if (Test-Path $path) {
  $found = Select-String -Path $path -Pattern 'picked != null && mounted' -SimpleMatch -Quiet
  if ($found) {
    Write-Host "  [PASS] lib/screens/liveclass/create_live_class_screen.dart -> Date/time picker mounted-check fix" -ForegroundColor Green
    $pass++
  } else {
    Write-Host "  [FAIL] lib/screens/liveclass/create_live_class_screen.dart -> MISSING: Date/time picker mounted-check fix" -ForegroundColor Red
    $fail++
  }
} else {
  Write-Host "  [MISSING FILE] lib/screens/liveclass/create_live_class_screen.dart" -ForegroundColor Red
  $fail++
}

Write-Host ""
Write-Host "TOTAL: $pass passed, $fail failed" -ForegroundColor Yellow