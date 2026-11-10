"""Generates the shared mock-backend fixtures (scenario "default") for the iOS app.

Test user "Alex": AI mode, gain_weight, intermediate, 4-day Upper/Lower program
(Mon/Tue/Thu/Fri), week 3 of an 8-week bulk, with three weeks of logged history
that progresses weight week to week. Dates are tokens expanded at runtime by
FixtureTransport, so the data always lines up with "today".

Run:  python ios/scripts/mock-fixtures/make_default.py
Screen-specific fixtures are hand-written next to these (same folder) by whoever
owns that operation; this script only (re)writes the files listed in SHARED.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Packages", "IntentKit", "Sources", "IntentAPI", "Fixtures", "default")
USER = "user_mock_alex"


def ex(name, sets, reps, muscle, rpe=8, rest=120, cue=None, secondary=None, unilateral=False):
    return {
        "name": name, "sets": sets, "reps": reps, "rpe": rpe, "restSeconds": rest,
        "cue": cue, "muscle": muscle, "secondaryMuscle": secondary,
        "isUnilateral": unilateral, "kind": "lift",
    }


def checklist(name, rounds, seconds, category):
    return {
        "name": name, "sets": rounds, "reps": f"{seconds // 60}:{seconds % 60:02d}", "muscle": "",
        "kind": "checklist", "targetType": "duration", "targetSeconds": seconds,
        "category": category, "isUnilateral": False,
    }


DAYS = [
    {"dayNumber": 1, "label": "Upper A", "focus": "Chest & back strength", "estimatedDurationMinutes": 62, "exercises": [
        ex("Barbell Bench Press", 3, "6-8", "Chest", rest=180, cue="Pause briefly on the chest, drive feet into the floor", secondary="Triceps"),
        ex("Chest-Supported Row", 3, "8-10", "Upper Back", cue="Pull elbows to hips, squeeze 1s", secondary="Lats"),
        ex("Seated Dumbbell Shoulder Press", 3, "8-10", "Shoulders", secondary="Triceps"),
        ex("Lat Pulldown", 3, "10-12", "Lats", rest=90, secondary="Biceps"),
        ex("Incline Dumbbell Curl", 2, "10-12", "Biceps", rpe=9, rest=75),
        ex("Cable Triceps Pushdown", 2, "10-12", "Triceps", rpe=9, rest=75),
        checklist("Thoracic Mobility", 1, 150, "mobility"),
    ]},
    {"dayNumber": 2, "label": "Lower A", "focus": "Squat pattern & quads", "estimatedDurationMinutes": 58, "exercises": [
        ex("Back Squat", 3, "5-7", "Quads", rest=180, cue="Brace before each rep, knees track toes", secondary="Glutes"),
        ex("Romanian Deadlift", 3, "8-10", "Hamstrings", rest=150, secondary="Glutes"),
        ex("Bulgarian Split Squat", 2, "8-10", "Quads", rest=90, secondary="Glutes", unilateral=True),
        ex("Seated Leg Curl", 3, "10-12", "Hamstrings", rpe=9, rest=75),
        ex("Standing Calf Raise", 3, "10-15", "Calves", rpe=9, rest=60),
        checklist("Plank", 2, 45, "core"),
    ]},
    {"dayNumber": 3, "label": "Upper B", "focus": "Shoulders & arms volume", "estimatedDurationMinutes": 60, "exercises": [
        ex("Incline Dumbbell Press", 3, "8-10", "Chest", rest=150, secondary="Shoulders"),
        ex("Weighted Pull-Up", 3, "6-8", "Lats", rest=150, secondary="Biceps"),
        ex("Cable Lateral Raise", 3, "12-15", "Shoulders", rpe=9, rest=60, unilateral=True),
        ex("Seated Cable Row", 3, "10-12", "Upper Back", rest=90),
        ex("EZ-Bar Curl", 2, "8-10", "Biceps", rpe=9, rest=75),
        ex("Overhead Triceps Extension", 2, "10-12", "Triceps", rpe=9, rest=75),
    ]},
    {"dayNumber": 4, "label": "Lower B", "focus": "Hinge & posterior chain", "estimatedDurationMinutes": 55, "exercises": [
        ex("Trap Bar Deadlift", 3, "5-6", "Glutes", rest=180, secondary="Hamstrings"),
        ex("Leg Press", 3, "10-12", "Quads", rest=120),
        ex("Hip Thrust", 3, "8-10", "Glutes", rest=120, secondary="Hamstrings"),
        ex("Leg Extension", 2, "12-15", "Quads", rpe=9, rest=60),
        ex("Seated Calf Raise", 3, "12-15", "Calves", rpe=9, rest=60),
        checklist("Hip Flexor Stretch", 1, 120, "stretch"),
    ]},
]

# Starting working weight (kg) and typical reps per lift; +2.5 kg per week for the big lifts.
START = {
    "Barbell Bench Press": (80, 7), "Chest-Supported Row": (30, 9), "Seated Dumbbell Shoulder Press": (24, 9),
    "Lat Pulldown": (65, 11), "Incline Dumbbell Curl": (12, 11), "Cable Triceps Pushdown": (30, 11),
    "Back Squat": (100, 6), "Romanian Deadlift": (90, 9), "Bulgarian Split Squat": (20, 9),
    "Seated Leg Curl": (45, 11), "Standing Calf Raise": (80, 12),
    "Incline Dumbbell Press": (30, 9), "Weighted Pull-Up": (10, 7), "Cable Lateral Raise": (8, 13),
    "Seated Cable Row": (60, 11), "EZ-Bar Curl": (35, 9), "Overhead Triceps Extension": (25, 11),
    "Trap Bar Deadlift": (140, 5), "Leg Press": (180, 11), "Hip Thrust": (110, 9),
    "Leg Extension": (55, 13), "Seated Calf Raise": (50, 13),
}
BIG = {"Barbell Bench Press", "Back Squat", "Romanian Deadlift", "Trap Bar Deadlift", "Leg Press", "Hip Thrust", "Seated Cable Row", "Lat Pulldown"}
SCHEDULE_DOW = {1: "mon", 2: "tue", 3: "thu", 4: "fri"}

PROGRAM = {
    "id": 12, "userId": USER, "weekNumber": 3, "programName": "Upper Lower", "splitType": "upper_lower",
    "programHighlights": [
        {"title": "Built around your bench", "detail": "Chest is a priority, so it gets two heavy exposures a week with the bench press leading Upper A."},
        {"title": "Moderate volume, room to grow", "detail": "About 14 hard sets per muscle each week. Volume climbs only once your logs show you are recovering."},
        {"title": "Four days, two rest days between blocks", "detail": "Mon/Tue and Thu/Fri keep each muscle on a 72-hour rhythm."},
    ],
    "aiGenerated": True, "days": DAYS, "generatedAt": "{{dowtime:mon:-2}}",
    "longTermPhase": "gain_weight", "shortTermPhase": "bulk", "energyBalance": "surplus",
    "trainingWorkload": {"daysTrained": 4, "totalVolumeSets": 62},
    "longTermGoalWeight": 84, "shortTermGoalWeight": 80.5, "dailyStepTarget": 8000, "dailyCalorieTarget": 3100,
    "weekInPhase": 3, "phaseTotalWeeks": 8,
    "cardioIntensity": {"bpmMin": 110, "bpmMax": 130, "level": "low"},
    "startDate": "{{dow:mon:-2}}",
    "schedule": {"mode": "fixed", "slots": [1, 2, None, 3, 4, None, None]},
}

PROFILE = {
    "userId": USER, "name": "Alex", "mode": "ai", "goal": "gain_weight", "experience": "intermediate",
    "trainingDays": 4, "equipment": ["barbell", "dumbbells", "cables", "machines"],
    "age": 27, "sex": "male", "weight": 78.4, "weightUnit": "kg", "goalWeight": 84,
    "activityLevel": "moderate", "preferredRestDays": ["wednesday", "saturday", "sunday"],
    "injuries": None, "injurySeverity": None, "priorityMuscles": ["Chest", "Shoulders"],
    "dailyCalorieTarget": 3100, "dailyStepTarget": 8000, "cardioDays": ["wednesday"], "cardioMinutes": 25,
    "onboardingComplete": True, "onboardingCompletedAt": "{{dowtime:mon:-5}}",
    "calibrationWalkthroughSeenAt": "{{dowtime:mon:-5}}", "calibrationBriefingSeenAt": "{{dowtime:mon:-5}}",
    "programPageTourSeenAt": "{{dowtime:mon:-5}}", "weightLoggingTourSeenAt": "{{dowtime:mon:-5}}",
    "dashboardTourSeenAt": "{{dowtime:mon:-5}}", "calendarTourSeenAt": "{{dowtime:mon:-5}}",
    "createdAt": "{{dowtime:mon:-5}}",
}


def logged(day, week_offset, week_index, log_id):
    exercises = []
    for e in day["exercises"]:
        if e["kind"] == "checklist":
            exercises.append({"name": e["name"], "muscle": "", "sets": [], "kind": "checklist",
                              "completedRounds": e["sets"], "targetSeconds": e["targetSeconds"],
                              "category": e["category"], "notes": None})
            continue
        base, reps = START[e["name"]]
        step = 2.5 if e["name"] in BIG else 1
        weight = base + step * week_index
        sets = []
        for n in range(1, e["sets"] + 1):
            r = max(reps - (n - 1), 1)
            s = {"setNumber": n, "weight": weight, "reps": r, "rpe": min(e["rpe"] + (n - 1) // 2, 10),
                 "completed": True, "isNewPr": week_index == 2 and n == 1 and e["name"] in BIG}
            if e["isUnilateral"]:
                s.update({"reps": None, "repsLeft": r, "repsRight": r})
            sets.append(s)
        exercises.append({"name": e["name"], "muscle": e["muscle"], "sets": sets, "kind": "lift",
                          "notes": "Felt strong, add 2.5 next time" if week_index == 2 and e["name"] == "Barbell Bench Press" else None})
    dow = SCHEDULE_DOW[day["dayNumber"]]
    duration = day["estimatedDurationMinutes"] * 60 + (week_index * 97 % 400) - 200
    return {
        "id": log_id, "userId": USER, "date": f"{{{{dow:{dow}:{week_offset}}}}}", "dayNumber": day["dayNumber"],
        "weekNumber": week_index + 1, "dayLabel": day["label"], "mode": "ai", "loggingMode": "full",
        "calibrationFeedback": None, "exercisesLogged": exercises, "notes": None,
        "startedAt": f"{{{{dowtime:{dow}:{week_offset}}}}}", "durationSeconds": duration,
        "createdAt": f"{{{{dowtime:{dow}:{week_offset}}}}}",
    }


def workouts():
    logs = []
    log_id = 300
    # weeks -2, -1 fully logged (program weeks 1-2), plus Monday of this week (week 3).
    for week_index, week_offset in enumerate([-2, -1]):
        for day in DAYS:
            log_id += 1
            logs.append(logged(day, week_offset, week_index, log_id))
    log_id += 1
    logs.append(logged(DAYS[0], 0, 2, log_id))
    logs.sort(key=lambda l: l["id"], reverse=True)  # newest first, like the API
    return logs


CALIBRATION_STATUS = {
    "inCalibration": False, "calibrationDay": None, "startDate": "{{dow:mon:-5}}",
    "reviewOpensOn": None, "lastReviewDate": None, "autoExitOn": None, "reviewOpen": False,
    "reviewBlockedReason": "not_in_calibration", "nextReviewAvailableOn": None, "paused": False,
    "autoExitDue": False, "checks": None, "sessions": [], "feedbackSummary": None, "latestReview": None,
}

SUBSCRIPTION = {"userId": USER, "plan": "pro", "status": "active", "stripeCustomerId": None,
                "stripeSubscriptionId": None, "currentPeriodEnd": "{{datetime:24}}"}

INDEPENDENT_PROGRAM = {
    **PROGRAM, "id": 9, "programName": "My Push Pull Legs", "splitType": "custom", "aiGenerated": False,
    "programHighlights": [], "longTermPhase": None, "shortTermPhase": None, "energyBalance": None,
    "trainingWorkload": None, "weekInPhase": None, "phaseTotalWeeks": None, "cardioIntensity": None,
    "schedule": None, "generatedAt": "{{dowtime:mon:-8}}", "startDate": None,
    "days": [{**d, "estimatedDurationMinutes": None} for d in DAYS[:3]],
}

SHARED = {
    "getProfile": {"status": 200, "body": PROFILE},
    "getCurrentProgram": {"status": 200, "body": PROGRAM},
    "listPrograms": {"status": 200, "body": [PROGRAM, INDEPENDENT_PROGRAM]},
    "getCalibrationStatus": {"status": 200, "body": CALIBRATION_STATUS},
    "listWorkouts": {"status": 200, "body": workouts()},
    "getRecentWorkouts": {"status": 200, "body": workouts()[:3]},
    "getSubscription": {"status": 200, "body": SUBSCRIPTION},
    "healthCheck": {"status": 200, "body": {"status": "ok"}},
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for op, payload in SHARED.items():
        with open(os.path.join(OUT, f"{op}.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.write("\n")
    print(f"wrote {len(SHARED)} fixtures to {OUT}")
