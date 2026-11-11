module loading

-- What a section of a screen may show while its part loads.
-- Alloy 6. Open in the Analyzer and execute every command below.

abstract sig Phase {}
one sig WaitingShort, Waiting, WaitingLong, Held, Arrived, Empty, Failed extends Phase {}

abstract sig Answer {}
one sig Items, NoItems, Failure extends Answer {}

sig Account {}

one sig Session { var signedIn: one Account }

sig Part {
  var answer: lone Answer,   -- what the server said in this load, if it has
  var copy: lone Account     -- the account the stored copy was fetched for
}

sig Section {
  part: one Part,
  var phase: one Phase
}

-- A value computed from several parts, such as the weighted average.
sig Computed { inputs: some Part }
one sig Screen { var shown: set Computed }

fact oneSectionPerPart { all disj s1, s2: Section | s1.part != s2.part }

fun content: set Phase { Held + Arrived }

pred available[p: Part] {
  p.answer in Items + NoItems or p.copy = Session.signedIn
}

pred start {
  no answer
  copy in Part -> Session.signedIn
  no Screen.shown
  all s: Section |
    (some s.part.copy implies s.phase = Held else s.phase = WaitingShort)
}

-- 300 ms and 3 s pass for a section that is still waiting.
pred tick[s: Section] {
  (s.phase = WaitingShort and s.phase' = Waiting) or
  (s.phase = Waiting and s.phase' = WaitingLong)
  all o: Section - s | o.phase' = o.phase
  answer' = answer
  copy' = copy
  signedIn' = signedIn
  shown' = shown
}

-- The server answers for a part, or the request fails.
pred answers[p: Part, a: Answer] {
  no p.answer
  p.answer' = a
  all q: Part - p | q.answer' = q.answer
  (a = Failure implies p.copy' = p.copy else p.copy' = Session.signedIn)
  all q: Part - p | q.copy' = q.copy
  all s: part.p {
    a = Items implies s.phase' = Arrived
    a = NoItems implies s.phase' = Empty
    a = Failure implies (s.phase = Held implies s.phase' = Held else s.phase' = Failed)
  }
  all s: Section - part.p | s.phase' = s.phase
  signedIn' = signedIn
  shown' = shown
}

-- The student taps the retry control of a failed section.
pred retry[s: Section] {
  s.phase = Failed
  s.phase' = Waiting
  no s.part.answer'
  all q: Part - s.part | q.answer' = q.answer
  all o: Section - s | o.phase' = o.phase
  copy' = copy
  signedIn' = signedIn
  shown' = shown
}

-- A later refresh starts for a section that shows fetched content.
pred refresh[s: Section] {
  s.phase = Arrived
  s.phase' = Held
  no s.part.answer'
  all q: Part - s.part | q.answer' = q.answer
  all o: Section - s | o.phase' = o.phase
  copy' = copy
  signedIn' = signedIn
  shown' = shown
}

-- The app puts a computed value on screen.
pred show[c: Computed] {
  c not in Screen.shown
  all p: c.inputs | available[p]
  Screen.shown' = Screen.shown + c
  answer' = answer
  copy' = copy
  phase' = phase
  signedIn' = signedIn
}

-- The student signs out and another account signs in.
pred signOut[a: Account] {
  a != Session.signedIn
  Session.signedIn' = a
  no answer'
  no copy'
  no Screen.shown'
  all s: Section | s.phase' = WaitingShort
}

pred stutter {
  answer' = answer
  copy' = copy
  phase' = phase
  signedIn' = signedIn
  shown' = shown
}

fact traces {
  start
  always (
    stutter
    or (some s: Section | tick[s] or retry[s] or refresh[s])
    or (some p: Part, a: Answer | answers[p, a])
    or (some c: Computed | show[c])
    or (some a: Account | signOut[a])
  )
}

-- R2: no empty state before the part answered.
assert EmptyOnlyAfterAnswer {
  always all s: Section | s.phase = Empty implies s.part.answer = NoItems
}

-- R3: a computed value is visible only while all its inputs are available.
assert ComputedNeedsAllInputs {
  always all c: Screen.shown, p: c.inputs | available[p]
}

-- R6, R17: a failure never takes content off the screen.
assert ContentNeverLost {
  always all s: Section |
    (s.phase in content and Session.signedIn' = Session.signedIn)
      implies s.phase' in content + Empty
}

-- R14, R40: a stored copy belongs to the account signed in.
assert CopyBelongsToSession {
  always all p: Part | p.copy in Session.signedIn
}

assert HeldShowsOwnCopy {
  always all s: Section | s.phase = Held implies s.part.copy = Session.signedIn
}

-- Scenarios: the model is not vacuous.
run firstSignIn {
  no copy
  #Section = 3
  eventually all s: Section | s.phase = Arrived
} for 4 but 10 steps

run slowThenRetried {
  some s: Section |
    eventually (s.phase = WaitingLong and eventually (s.phase = Failed and eventually s.phase = Arrived))
} for 4 but 12 steps

run averageAppears {
  no copy
  some c: Computed | #c.inputs = 2 and eventually c in Screen.shown
} for 4 but 10 steps

check EmptyOnlyAfterAnswer for 4 but 12 steps
check ComputedNeedsAllInputs for 4 but 12 steps
check ContentNeverLost for 4 but 12 steps
check CopyBelongsToSession for 4 but 12 steps
check HeldShowsOwnCopy for 4 but 12 steps
