import SwiftUI

/// A small cat or dog that turns up during a break and does one cute thing (waves, stretches, naps,
/// plays, watches a butterfly, sends hearts; cats also groom, dogs also bark and get the zoomies),
/// saying something now and then. Each break picks a different coat, entrance side and activity
/// from the last one. Drawn in code.
struct BreakPet: View {
    /// Distance from the bottom of the screen to the pet's paws.
    let groundInset: CGFloat
    /// One break's pet, picked when the overlay opens. The view is rebuilt every tick,
    /// so nothing may be picked here.
    let cast: Cast

    static let scale: CGFloat = 1.1
    static let size = CGSize(width: PetFigure.box.width * scale, height: PetFigure.box.height * scale)

    enum Choice: String, CaseIterable {
        case both, cats, dogs, off

        var title: String {
            switch self {
            case .both: return "Cats & Dogs"
            case .cats: return "Cats"
            case .dogs: return "Dogs"
            case .off: return "Off"
            }
        }
    }

    private static let choiceKey = "breakPet"
    static var choice: Choice {
        get {
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: choiceKey), let choice = Choice(rawValue: raw) { return choice }
            // Before dogs, there was only an on/off "Break Cat" switch.
            if defaults.object(forKey: "breakCat") as? Bool == false { return .off }
            return .both
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    final class Cast {
        let coat: PetCoat
        let show: PetShow
        let start = Date()

        /// Nil when pets are switched off.
        init?(choice: Choice, water: Bool) {
            let species: PetCoat.Species
            switch choice {
            case .off: return nil
            case .cats: species = .cat
            case .dogs: species = .dog
            case .both:   // take turns
                let last = UserDefaults.standard.string(forKey: "breakPetLastSpecies")
                species = last == PetCoat.Species.cat.rawValue ? .dog : .cat
            }
            UserDefaults.standard.set(species.rawValue, forKey: "breakPetLastSpecies")

            coat = BreakPet.pickFresh(PetCoat.all(species), key: "breakPetLastCoat.\(species.rawValue)", id: \.name)
            let entrance = BreakPet.pickFresh(PetShow.Entrance.allCases, key: "breakPetLastEntrance", id: \.rawValue)
            let action = BreakPet.pickFresh(PetShow.Action.all(species), key: "breakPetLastAction.\(species.rawValue)",
                                            id: \.rawValue)
            show = PetShow(species: species, entrance: entrance, action: action, water: water)
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                scene(t: context.date.timeIntervalSince(cast.start), in: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func scene(t: Double, in size: CGSize) -> some View {
        let groundY = size.height - groundInset
        let frame = cast.show.frame(at: t, width: size.width, groundY: groundY)
        let pose = frame.pose
        let stretch = 1 + (1 - pose.squash) * 0.8
        let headTop = Self.toScene(PetFigure.headTop(pose), pose: pose, groundY: groundY)
        let bubbleX = min(max(headTop.x, 170), size.width - 170)

        return ZStack {
            if let string = frame.string {
                Path { p in
                    p.move(to: string.0)
                    p.addLine(to: string.1)
                }
                .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
            }

            PetFigure(pose: pose, coat: cast.coat, time: t)
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(x: (pose.facingRight ? 1 : -1) * stretch, y: pose.squash, anchor: .bottom)
                .offset(y: pose.lift)
                // Everything below the ground line is hidden, so the pet can rise from behind the Dock.
                .frame(width: Self.size.width, height: groundY, alignment: .bottom)
                .clipped()
                .position(x: pose.x, y: groundY / 2)

            ForEach(Array(frame.props.enumerated()), id: \.offset) { _, prop in
                Text(prop.text)
                    .font(.system(size: prop.size, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .scaleEffect(x: prop.scaleX, y: 1)
                    .rotationEffect(.radians(prop.rotation))
                    .opacity(prop.opacity)
                    .position(prop.position)
            }

            if let bubble = frame.bubble {
                SpeechBubble(text: bubble.text, tailOffset: headTop.x - bubbleX)
                    .scaleEffect(0.7 + 0.3 * bubble.progress, anchor: .bottom)
                    .opacity(min(1, bubble.progress))
                    .frame(width: 340, height: 140, alignment: .bottom)
                    .position(x: bubbleX, y: headTop.y - 14 - 70)
            }
        }
    }

    /// Converts a point in the pet's drawing box to screen coordinates.
    static func toScene(_ p: CGPoint, pose: PetPose, groundY: CGFloat) -> CGPoint {
        let sign: CGFloat = pose.facingRight ? 1 : -1
        return CGPoint(x: pose.x + (p.x - PetFigure.box.width / 2) * scale * sign,
                       y: groundY + pose.lift - (PetFigure.box.height - p.y) * scale)
    }

    /// Random pick that differs from the previous break's, so consecutive breaks look different.
    fileprivate static func pickFresh<T>(_ all: [T], key: String, id: (T) -> String) -> T {
        let last = UserDefaults.standard.string(forKey: key)
        let pick = all.filter { id($0) != last }.randomElement() ?? all[0]
        UserDefaults.standard.set(id(pick), forKey: key)
        return pick
    }
}

// MARK: - Timing helpers

private func smooth(_ x: Double) -> CGFloat {
    let t = min(max(x, 0), 1)
    return CGFloat(t * t * (3 - 2 * t))
}

/// 0 → 1 over `dur` seconds from `start`.
private func ramp(_ t: Double, _ start: Double, _ dur: Double) -> CGFloat { smooth((t - start) / dur) }

/// Up over `fade`, held, and back down so it ends at `start + dur`.
private func pulse(_ t: Double, _ start: Double, _ dur: Double, _ fade: Double) -> CGFloat {
    ramp(t, start, fade) * (1 - ramp(t, start + dur - fade, fade))
}

private func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private extension CGPoint {
    func moved(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}

// MARK: - Show (what the pet does, over time)

struct PetPose {
    enum Eyes { case open, happy, closed }

    var x: CGFloat
    var facingRight: Bool
    var walking = false
    /// Floating down on the balloon: legs paddle, floppy ears fly up.
    var airborne = false
    /// Distance walked so far; drives the leg cycle so paws don't slide.
    var distance: CGFloat = 0
    /// Vertical offset from standing on the ground: negative is up in the air, positive is below the ground.
    var lift: CGFloat = 0
    /// 1 is normal; less is squashed flat (landing).
    var squash: CGFloat = 1
    /// Blend amounts from standing toward sitting, lying (loaf) and a play-bow stretch.
    var sit: CGFloat = 0
    var lie: CGFloat = 0
    var bow: CGFloat = 0
    /// Near front paw raised (0...1) toward `pawAngle`.
    var pawUp: CGFloat = 0
    var pawAngle: CGFloat = -2.4
    /// Raise from the shoulder instead of the elbow, for waving and reaching up.
    var pawHigh: CGFloat = 0
    var headTilt: CGFloat = 0
    /// Where the pupils look, roughly -1...1 each way, in the pet's own facing direction.
    var gaze = CGPoint.zero
    var eyes = Eyes.open
    var mouthOpen: CGFloat = 0
    /// Cats: tongue tip while grooming. Dogs: tongue out, panting.
    var tongue = false
}

struct PetProp {
    var text: String
    var position: CGPoint
    var size: CGFloat
    var opacity: Double = 1
    var rotation: Double = 0
    var scaleX: CGFloat = 1
}

struct PetFrame {
    var pose: PetPose
    var props: [PetProp] = []
    /// Balloon string, in screen coordinates.
    var string: (CGPoint, CGPoint)?
    var bubble: (text: String, progress: Double)?
}

/// Everything the pet does in one break: how it arrives, then one activity on a loop.
final class PetShow {
    enum Entrance: String, CaseIterable {
        case left, right, balloon, popUp
    }

    enum Action: String, CaseIterable {
        case wave, groom, stretch, nap, yarn, fetch, zoomies, bark, butterfly, hearts

        static func all(_ species: PetCoat.Species) -> [Action] {
            switch species {
            case .cat: return [.wave, .groom, .stretch, .nap, .yarn, .butterfly, .hearts]
            case .dog: return [.wave, .stretch, .nap, .fetch, .zoomies, .bark, .butterfly, .hearts]
            }
        }

        func line(_ species: PetCoat.Species) -> String {
            let dog = species == .dog
            switch self {
            case .wave: return dog ? "Paw! 🐾 Now look far away" : "Hi, human! 👋 Look far away for a bit"
            case .groom: return "Self-care o'clock. Blink slowly 😌"
            case .stretch: return dog ? "Big stretch! Your turn 🐶" : "Stretch with me! 🐾"
            case .nap: return dog ? "Zzz… rest your eyes too 😴" : "Shh… rest your eyes too 😴"
            case .yarn: return "Playtime! Eyes off the screen 🧶"
            case .fetch: return "Fetch break! Eyes off the screen 🎾"
            case .zoomies: return "Zoomies! Get up and move a bit 🏃"
            case .bark: return "Woof! Look at something far away 👀"
            case .butterfly: return "Ooh! Look at something far away 🦋"
            case .hearts: return dog ? "You're my favourite human 💗" : "I like you. Take a deep breath 💗"
            }
        }
    }

    let species: PetCoat.Species
    let entrance: Entrance
    let action: Action
    private let lines: [String]

    private var plannedWidth: CGFloat = -1
    private var spot: CGFloat = 0
    private var startX: CGFloat = 0
    private var facingRight = true
    /// When the entrance is over and the activity starts.
    private var arrival: Double = 0

    private static let walkSpeed: CGFloat = 130   // points per second

    init(species: PetCoat.Species, entrance: Entrance, action: Action, water: Bool) {
        self.species = species
        self.entrance = entrance
        self.action = action
        var general = [
            "Look at something far away 👀",
            "Roll your shoulders back",
            "Unclench your jaw",
            species == .dog ? "Woof. Eyes off the screen, human" : "Meow. Eyes off the screen, human",
        ]
        if water { general += ["Drink some water 💧", "Have you had water lately? 💧"] }
        lines = [action.line(species)] + general.shuffled()
    }

    private func plan(width w: CGFloat) {
        plannedWidth = w
        // Keep the spot far enough from the edges for the bubble (and the zoomies) to fit.
        var lo = max(180, w * 0.12), hi = min(w - 180, w * 0.88)
        if hi <= lo { lo = w / 2; hi = w / 2 }
        switch entrance {
        case .left:
            facingRight = true
            startX = -100
            spot = .random(in: lo...min(hi, lo + w * 0.2))
            arrival = Double((spot - startX) / Self.walkSpeed)
        case .right:
            facingRight = false
            startX = w + 100
            spot = .random(in: max(lo, hi - w * 0.2)...hi)
            arrival = Double((startX - spot) / Self.walkSpeed)
        case .balloon, .popUp:
            spot = .random(in: lo...hi)
            startX = spot
            facingRight = spot < w / 2   // face into the screen, where the toys are
            arrival = entrance == .balloon ? 3.3 : 1.2
        }
    }

    func frame(at t: Double, width: CGFloat, groundY: CGFloat) -> PetFrame {
        if abs(width - plannedWidth) > 1 { plan(width: width) }
        var frame = PetFrame(pose: PetPose(x: spot, facingRight: facingRight))
        enter(t, &frame, groundY: groundY)
        if t >= arrival {
            let tau = t - arrival
            act(tau, &frame.pose, groundY: groundY)
            frame.props += props(tau, pose: frame.pose, groundY: groundY)

            // A line every 9 s, each shown for 5.5 s.
            let since = tau - 0.5
            if since >= 0 {
                let i = Int(since / 9)
                let local = since - Double(i) * 9
                if local < 5.5 {
                    frame.bubble = (lines[i % lines.count], Self.pop(elapsed: local, remaining: 5.5 - local))
                }
            }
        }
        return frame
    }

    // MARK: Entrances

    private func enter(_ t: Double, _ frame: inout PetFrame, groundY: CGFloat) {
        let petHeight = BreakPet.size.height
        let dir: CGFloat = facingRight ? 1 : -1
        switch entrance {
        case .left, .right:
            if t < arrival {
                frame.pose.x = startX + (spot - startX) * CGFloat(t / arrival)
                frame.pose.walking = true
                frame.pose.distance = abs(frame.pose.x - startX)
                frame.pose.tongue = species == .dog
            }
        case .balloon:
            let height = groundY + petHeight * 1.6
            if t < 0.4 {
                frame.pose.lift = -height
            } else if t < 3.0 {
                let p = (t - 0.4) / 2.6
                frame.pose.lift = -height * CGFloat(pow(1 - p, 3))   // eases to a soft landing
                frame.pose.x = spot + CGFloat(sin(p * .pi * 3) * 18 * (1 - p))
                frame.pose.airborne = true
                frame.pose.eyes = .happy
                frame.pose.mouthOpen = 0.4
            } else if t < 3.3 {
                frame.pose.squash = 1 - 0.16 * CGFloat(sin((t - 3.0) / 0.3 * .pi))
            }
            // The balloon, held by a string on the pet's back, then let go to float away.
            if t < 3.0 {
                let anchor = BreakPet.toScene(PetFigure.backTop(frame.pose), pose: frame.pose, groundY: groundY)
                let balloon = CGPoint(x: anchor.x - dir * 8 + CGFloat(sin(t * 2.3)) * 4, y: anchor.y - 74)
                frame.string = (anchor, balloon.moved(0, 18))
                frame.props.append(PetProp(text: "🎈", position: balloon, size: 40, rotation: sin(t * 2.3) * 0.08))
            } else if t < 6 {
                let landed = PetPose(x: spot, facingRight: facingRight)
                let anchor = BreakPet.toScene(PetFigure.backTop(landed), pose: landed, groundY: groundY)
                let r = t - 3.0
                let balloon = CGPoint(x: anchor.x - dir * 8 + CGFloat(sin(r * 3)) * 12,
                                      y: anchor.y - 74 - CGFloat(r * 180 + r * r * 60))
                frame.props.append(PetProp(text: "🎈", position: balloon, size: 40,
                                           opacity: 1 - min(1, max(0, (r - 1.6) / 1.0)), rotation: sin(r * 3) * 0.12))
            }
        case .popUp:
            let depth = petHeight * 1.05
            if t < 0.6 {
                frame.pose.lift = depth
            } else if t < 1.15 {
                let q = (t - 0.6) / 0.55 - 1
                frame.pose.lift = depth * CGFloat(1 - (1 + 2.70158 * q * q * q + 1.70158 * q * q))   // slight hop
            }
            if t >= 0.6 && t < 2.0 {
                frame.pose.eyes = .happy
                frame.pose.mouthOpen = species == .dog ? 0 : 0.5
            }
            if t >= 1.0 && t < 2.0 {
                let top = BreakPet.toScene(PetFigure.headTop(frame.pose), pose: frame.pose, groundY: groundY)
                let p = (t - 1.0) / 1.0
                for (i, dx) in [-46.0, 50, -20].enumerated() {
                    let twinkle = 0.6 + 0.4 * sin(t * 14 + Double(i) * 2)
                    frame.props.append(PetProp(text: "✨",
                                               position: top.moved(CGFloat(dx), 30 - CGFloat(i) * 16 - CGFloat(p) * 10),
                                               size: 18, opacity: (1 - p) * twinkle))
                }
            }
        }
    }

    // MARK: Activities

    private func act(_ tau: Double, _ pose: inout PetPose, groundY: CGFloat) {
        switch action {
        case .wave:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 7)
            let w = pulse(c, 0.7, 3.0, 0.35)
            pose.pawUp = w
            pose.pawHigh = 1
            pose.pawAngle = -2.25 + CGFloat(sin(tau * 9)) * 0.3
            if w > 0.5 {
                pose.eyes = .happy
                if species == .cat { pose.mouthOpen = 0.55 }
            }
            pose.tongue = species == .dog
        case .groom:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 6)
            let g = pulse(c, 0.7, 3.4, 0.35)
            pose.pawUp = g
            pose.pawAngle = -2.75 + CGFloat(sin(tau * 7)) * 0.12
            pose.headTilt = 0.1 * g
            if g > 0.5 {
                pose.eyes = .happy
                pose.tongue = sin(tau * 7) > 0
            }
        case .stretch:
            let c = tau.truncatingRemainder(dividingBy: 9)
            pose.bow = pulse(c, 0.2, 3.0, 0.6)
            pose.sit = ramp(c, 4.0, 0.6) * (1 - ramp(c, 8.4, 0.5))
            pose.mouthOpen = pulse(c, 1.1, 1.6, 0.4)   // big yawn mid-stretch
            if pose.mouthOpen > 0.3 { pose.eyes = .closed }
            pose.tongue = species == .dog && c > 4.6
        case .nap:
            pose.sit = ramp(tau, 0, 0.5)
            pose.lie = ramp(tau, 1.8, 1.0)
            pose.mouthOpen = pulse(tau, 0.6, 1.0, 0.3)
            if tau > 2.3 || pose.mouthOpen > 0.3 { pose.eyes = .closed }
        case .yarn, .fetch:
            pose.gaze = CGPoint(x: 0.9, y: 0.6)
            pose.tongue = species == .dog
            guard tau >= 1.2 else { return }
            let c = (tau - 1.2).truncatingRemainder(dividingBy: 5.2)
            pose.bow = ramp(c, 0, 0.4) * 0.75 * (1 - ramp(c, 1.8, 0.25))
            if c < 1.8 { pose.lift = CGFloat(sin(c * 28)) * 0.8 }   // wiggle before the pounce
            if c >= 1.8 && c < 2.3 { pose.lift = -26 * CGFloat(sin((c - 1.8) / 0.5 * .pi)) }
            pose.pawUp = pulse(c, 1.8, 0.6, 0.15)
            pose.pawAngle = -1.9
            pose.sit = ramp(c, 2.3, 0.4) * (1 - ramp(c, 4.8, 0.4))
            if c > 2.5 && c < 3.6 { pose.eyes = .happy }
        case .zoomies:
            // Two laps back and forth at full speed, then a happy pant, on a loop.
            let range: CGFloat = 150, speed: CGFloat = 380
            let lap = Double(4 * range / speed)
            let c = tau.truncatingRemainder(dividingBy: lap * 2 + 2)
            pose.tongue = true
            if c < lap * 2 {
                let s = CGFloat(c) * speed
                let phase = (s + range).truncatingRemainder(dividingBy: 4 * range)
                let forward = phase < 2 * range
                let offset = forward ? phase - range : range - (phase - 2 * range)
                pose.x = spot + (facingRight ? 1 : -1) * offset
                pose.facingRight = forward == facingRight
                pose.walking = true
                pose.distance = s
            } else {
                pose.eyes = .happy
            }
        case .bark:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 2.6)
            let woof = max(pulse(c, 0.3, 0.35, 0.08), pulse(c, 0.8, 0.35, 0.08))
            pose.mouthOpen = woof * 0.9
            pose.headTilt = -0.12 * woof
            pose.tongue = woof < 0.1
            if c > 1.4 && c < 2.2 { pose.eyes = .happy }
        case .butterfly:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 5)
            let hop = pulse(c, 3.3, 0.8, 0.15)
            pose.sit *= 1 - 0.6 * hop
            if c >= 3.4 && c < 4.0 { pose.lift = -32 * CGFloat(sin((c - 3.4) / 0.6 * .pi)) }
            pose.pawUp = hop
            pose.pawHigh = 1
            pose.pawAngle = -2.1
            pose.mouthOpen = species == .cat ? 0.5 * hop : 0
            pose.tongue = species == .dog
            // Follow the butterfly with eyes and head.
            let b = butterfly(tau, groundY: groundY)
            let head = BreakPet.toScene(PetFigure.rig(for: pose).head, pose: pose, groundY: groundY)
            let dx = (b.x - head.x) * (facingRight ? 1 : -1), dy = b.y - head.y
            let len = max(1, sqrt(dx * dx + dy * dy))
            pose.gaze = CGPoint(x: dx / len, y: dy / len)
            pose.headTilt = 0.2 * (dy / len)
        case .hearts:
            pose.sit = ramp(tau, 0, 0.5)
            let c = tau.truncatingRemainder(dividingBy: 3.2)
            if c > 1.6 && c < 2.5 { pose.eyes = .happy }   // slow blink: "I love you"
            pose.headTilt = CGFloat(sin(tau * 1.1)) * 0.1
            pose.tongue = species == .dog
        }
    }

    private func props(_ tau: Double, pose: PetPose, groundY: CGFloat) -> [PetProp] {
        let dir: CGFloat = facingRight ? 1 : -1
        let top = BreakPet.toScene(PetFigure.headTop(pose), pose: pose, groundY: groundY)
        switch action {
        case .nap:
            return floating("z", from: top.moved(dir * 34, 26), after: 2.6, tau: tau, count: 3, every: 0.9,
                            period: 2.7, drift: dir * 30, size: 13, grow: 6)
        case .hearts:
            return floating("💗", from: top.moved(dir * 40, 30), after: 0.6, tau: tau, count: 3, every: 1.1,
                            period: 3.3, drift: dir * 34, size: 15, grow: 4)
        case .bark:
            let c = tau.truncatingRemainder(dividingBy: 2.6)
            return [0.3, 0.8].compactMap { start in
                let since = c - start
                guard since > 0 && since < 1.1 else { return nil }
                return PetProp(text: "Woof!", position: top.moved(dir * (48 + CGFloat(since) * 14), 22 - CGFloat(since) * 26),
                               size: 15, opacity: 1 - since / 1.1, rotation: Double(-dir) * 0.15)
            }
        case .yarn, .fetch:
            let ball = ballPosition(tau)
            let tennis = action == .fetch
            return [PetProp(text: tennis ? "🎾" : "🧶",
                            position: CGPoint(x: spot + dir * ball.x, y: groundY - (tennis ? 11 : 13) - ball.hop * (tennis ? 1.6 : 1)),
                            size: tennis ? 22 : 26, rotation: Double(dir * ball.x / 13))]
        case .butterfly:
            let flap = 0.45 + 0.55 * abs(sin(tau * 16))
            let heading: CGFloat = cos(tau * 0.8) >= 0 ? dir : -dir
            return [PetProp(text: "🦋", position: butterfly(tau, groundY: groundY), size: 24,
                            scaleX: CGFloat(flap) * -heading)]
        default:
            return []
        }
    }

    /// Repeating text that floats up and fades (z's, hearts).
    private func floating(_ text: String, from: CGPoint, after start: Double, tau: Double, count: Int, every: Double,
                          period: Double, drift: CGFloat, size: CGFloat, grow: CGFloat) -> [PetProp] {
        (0..<count).compactMap { k in
            let since = tau - start - Double(k) * every
            guard since > 0 else { return nil }
            let ph = since.truncatingRemainder(dividingBy: period)
            let p = CGFloat(ph / period)
            return PetProp(text: text,
                           position: from.moved(drift * p + CGFloat(sin(ph * 3 + Double(k))) * 5, -p * 70),
                           size: size + grow * p,
                           opacity: (1 - Double(p)) * min(1, ph * 4))
        }
    }

    /// Ball distance in front of the pet, and how high it bounces.
    private func ballPosition(_ tau: Double) -> (x: CGFloat, hop: CGFloat) {
        if tau < 1.2 { return (300 - 220 * CGFloat(1 - pow(1 - tau / 1.2, 2)), 0) }   // rolls in
        let c = (tau - 1.2).truncatingRemainder(dividingBy: 5.2)
        switch c {
        case ..<2.05:
            return (80, 0)
        case ..<3.05:   // batted away
            let p = (c - 2.05) / 1.0
            return (80 + 140 * CGFloat(1 - pow(1 - p, 2)), 16 * CGFloat(sin(min(p * 2, 1) * .pi)))
        case ..<3.6:
            return (220, 0)
        case ..<5.0:    // rolls back
            return (220 - 140 * smooth((c - 3.6) / 1.4), 0)
        default:
            return (80, 0)
        }
    }

    private func butterfly(_ tau: Double, groundY: CGFloat) -> CGPoint {
        let dir: CGFloat = facingRight ? 1 : -1
        let hover = CGPoint(x: spot + dir * (60 + 45 * CGFloat(sin(tau * 0.8))),
                            y: groundY - BreakPet.size.height * 1.3 + 22 * CGFloat(sin(tau * 1.9)))
        let from = CGPoint(x: spot + dir * 420, y: groundY - 380)
        return mix(from, hover, smooth(tau / 1.6))
    }

    /// Springy pop-in over 0.35 s (overshoots slightly past 1), fade-out over the last 0.25 s.
    private static func pop(elapsed: Double, remaining: Double) -> Double {
        let p = min(max(elapsed / 0.35, 0), 1) - 1
        let easeOutBack = 1 + 2.70158 * p * p * p + 1.70158 * p * p
        return min(easeOutBack, remaining / 0.25)
    }
}

// MARK: - Coats

/// Species, fur colours and markings for one kind of pet.
struct PetCoat {
    enum Species: String { case cat, dog }
    enum Ears { case pointy, floppy, folded }
    enum Tail { case cat, plume, whip, curl, stub }

    var name: String
    var species: Species
    var ears: Ears
    var tail: Tail
    var fur: Color
    /// Far-side legs, and the tail tip on pointed coats.
    var shade: Color
    var belly: Color
    var muzzle: Color
    var paw: Color
    /// Floppy or folded ears in their own colour.
    var earColor: Color?
    var stripes: Color?
    /// Siamese-style darker ears, face mask, legs and tail.
    var points: Color?
    var patches: [Color] = []
    /// Dalmatian spots.
    var spots: Color?
    /// Beagle-style patch over the back.
    var saddle: Color?
    /// Light lower face and cheeks (shiba, corgi, husky).
    var face: Color?
    /// Coloured eyes get a big pupil; nil draws plain dark eyes.
    var iris: Color?
    var whisker: Color
    /// Dark coats get a soft light rim so they stand out on the dimmed screen.
    var dark: Bool

    init(_ name: String, _ species: Species, ears: Ears = .pointy, tail: Tail = .cat,
         fur: UInt32, shade: UInt32, belly: UInt32, muzzle: UInt32? = nil, paw: UInt32? = nil,
         earColor: UInt32? = nil, stripes: UInt32? = nil, points: UInt32? = nil, patches: [UInt32] = [],
         spots: UInt32? = nil, saddle: UInt32? = nil, face: UInt32? = nil, iris: UInt32? = nil,
         whisker: UInt32 = 0xFFFFFF, dark: Bool = false) {
        self.name = name
        self.species = species
        self.ears = ears
        self.tail = tail
        self.fur = Color(hex: fur)
        self.shade = Color(hex: shade)
        self.belly = Color(hex: belly)
        self.muzzle = Color(hex: muzzle ?? belly)
        self.paw = Color(hex: paw ?? belly)
        self.earColor = earColor.map { Color(hex: $0) }
        self.stripes = stripes.map { Color(hex: $0) }
        self.points = points.map { Color(hex: $0) }
        self.patches = patches.map { Color(hex: $0) }
        self.spots = spots.map { Color(hex: $0) }
        self.saddle = saddle.map { Color(hex: $0) }
        self.face = face.map { Color(hex: $0) }
        self.iris = iris.map { Color(hex: $0) }
        self.whisker = Color(hex: whisker)
        self.dark = dark
    }

    static func all(_ species: Species) -> [PetCoat] { species == .cat ? cats : dogs }

    static let cats: [PetCoat] = [
        PetCoat("ginger", .cat, fur: 0xF6A15B, shade: 0xD9783A, belly: 0xFFE6CC, stripes: 0xE07F3E),
        PetCoat("grey tabby", .cat, fur: 0xA9B1BC, shade: 0x7D8693, belly: 0xEEF1F4, stripes: 0x7A8390, iris: 0x8FD45E),
        PetCoat("black", .cat, fur: 0x3E3947, shade: 0x2A2631, belly: 0x3E3947, muzzle: 0x4A4454, iris: 0xF5D042, dark: true),
        PetCoat("tuxedo", .cat, fur: 0x3E3947, shade: 0x2A2631, belly: 0xF7F4EF, iris: 0x8FD45E, dark: true),
        PetCoat("white", .cat, fur: 0xF6F3EE, shade: 0xD9D3CA, belly: 0xFFFFFF, iris: 0x6EC6F0, whisker: 0xB5ADA3),
        PetCoat("siamese", .cat, fur: 0xF2E4CF, shade: 0x4A372D, belly: 0xFBF3E6, muzzle: 0x5A4336, paw: 0x5A4336,
                points: 0x5A4336, iris: 0x6EC6F0),
        PetCoat("calico", .cat, fur: 0xF8F2E8, shade: 0xD9D0C2, belly: 0xFFFFFF, patches: [0xF2A15A, 0x3E3947],
                iris: 0xE8A93C, whisker: 0xB5ADA3),
    ]

    static let dogs: [PetCoat] = [
        PetCoat("golden retriever", .dog, ears: .floppy, tail: .plume, fur: 0xEDB565, shade: 0xC98C3E, belly: 0xF7DCA8,
                muzzle: 0xF5D093, earColor: 0xD99A4C),
        PetCoat("shiba inu", .dog, tail: .curl, fur: 0xE8954A, shade: 0xC4732F, belly: 0xFFF3E3, face: 0xFFF3E3),
        PetCoat("dalmatian", .dog, ears: .floppy, tail: .whip, fur: 0xFAF9F6, shade: 0xDCDAD3, belly: 0xFFFFFF,
                earColor: 0x3A3540, spots: 0x3A3540),
        PetCoat("corgi", .dog, tail: .stub, fur: 0xEE9A4D, shade: 0xC9752C, belly: 0xFFFFFF, face: 0xFFFFFF),
        PetCoat("husky", .dog, tail: .curl, fur: 0x8D96A3, shade: 0x6B7480, belly: 0xFFFFFF, face: 0xFFFFFF,
                iris: 0x6EC6F0),
        PetCoat("pug", .dog, ears: .folded, tail: .curl, fur: 0xE8CB9F, shade: 0xC9A672, belly: 0xF3DEB9,
                muzzle: 0x4A3F45, earColor: 0x4A3F45),
        PetCoat("chocolate lab", .dog, ears: .floppy, tail: .whip, fur: 0x8A5C3C, shade: 0x6A452B, belly: 0x9A6B4A,
                muzzle: 0xA97A57, earColor: 0x704A30),
        PetCoat("beagle", .dog, ears: .floppy, tail: .whip, fur: 0xDB9853, shade: 0xB57534, belly: 0xFFFFFF,
                paw: 0xFFFFFF, earColor: 0xC47A3A, saddle: 0x3A3540),
    ]
}

// MARK: - Drawing

/// One chibi pet, side-on with its face turned to the viewer. Drawn facing right.
struct PetFigure: View {
    let pose: PetPose
    let coat: PetCoat
    let time: Double

    /// Drawing box in unscaled points; the paws touch the bottom edge.
    static let box = CGSize(width: 150, height: 106)

    /// Body layout for one posture; postures blend into each other.
    struct Rig {
        var body: CGPoint
        var bodySize: CGSize
        var bodyAngle: CGFloat
        var head: CGPoint
        var frontHip: CGPoint
        var frontLength: CGFloat
        var frontAngle: CGFloat
        var backHip: CGPoint
        var backLength: CGFloat
        var backAngle: CGFloat
        /// Sitting thigh, faded in as the back legs fade out.
        var haunch: CGFloat
        /// Cat tail: base, two control points and tip. Dog tails only use the base.
        var tail: [CGPoint]

        func blended(_ o: Rig, _ t: CGFloat) -> Rig {
            guard t > 0 else { return self }
            func f(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            return Rig(body: mix(body, o.body, t),
                       bodySize: CGSize(width: f(bodySize.width, o.bodySize.width),
                                        height: f(bodySize.height, o.bodySize.height)),
                       bodyAngle: f(bodyAngle, o.bodyAngle),
                       head: mix(head, o.head, t),
                       frontHip: mix(frontHip, o.frontHip, t), frontLength: f(frontLength, o.frontLength),
                       frontAngle: f(frontAngle, o.frontAngle),
                       backHip: mix(backHip, o.backHip, t), backLength: f(backLength, o.backLength),
                       backAngle: f(backAngle, o.backAngle),
                       haunch: f(haunch, o.haunch),
                       tail: zip(tail, o.tail).map { mix($0, $1, t) })
        }
    }

    private static let standing = Rig(
        body: CGPoint(x: 62, y: 74), bodySize: CGSize(width: 66, height: 34), bodyAngle: 0,
        head: CGPoint(x: 96, y: 47),
        frontHip: CGPoint(x: 82, y: 82), frontLength: 16, frontAngle: 0,
        backHip: CGPoint(x: 46, y: 82), backLength: 16, backAngle: 0,
        haunch: 0,
        tail: [CGPoint(x: 32, y: 72), CGPoint(x: 14, y: 74), CGPoint(x: 16, y: 44), CGPoint(x: 12, y: 36)])

    private static let sitting = Rig(
        body: CGPoint(x: 58, y: 74), bodySize: CGSize(width: 60, height: 36), bodyAngle: -1.05,
        head: CGPoint(x: 80, y: 41),
        frontHip: CGPoint(x: 74, y: 72), frontLength: 26, frontAngle: 0,
        backHip: CGPoint(x: 46, y: 86), backLength: 12, backAngle: 0,
        haunch: 1,
        tail: [CGPoint(x: 36, y: 96), CGPoint(x: 14, y: 102), CGPoint(x: 6, y: 84), CGPoint(x: 14, y: 70)])

    private static let lying = Rig(
        body: CGPoint(x: 64, y: 88), bodySize: CGSize(width: 74, height: 27), bodyAngle: 0,
        head: CGPoint(x: 96, y: 72),
        frontHip: CGPoint(x: 86, y: 96), frontLength: 14, frontAngle: -1.45,
        backHip: CGPoint(x: 48, y: 92), backLength: 6, backAngle: 0,
        haunch: 0,
        tail: [CGPoint(x: 30, y: 92), CGPoint(x: 12, y: 99), CGPoint(x: 40, y: 103), CGPoint(x: 62, y: 99)])

    private static let bowing = Rig(
        body: CGPoint(x: 60, y: 76), bodySize: CGSize(width: 66, height: 32), bodyAngle: 0.38,
        head: CGPoint(x: 102, y: 68),
        frontHip: CGPoint(x: 86, y: 92), frontLength: 24, frontAngle: -1.45,
        backHip: CGPoint(x: 40, y: 72), backLength: 26, backAngle: 0,
        haunch: 0,
        tail: [CGPoint(x: 30, y: 64), CGPoint(x: 16, y: 52), CGPoint(x: 28, y: 24), CGPoint(x: 20, y: 16)])

    static func rig(for pose: PetPose) -> Rig {
        standing.blended(sitting, pose.sit).blended(lying, pose.lie).blended(bowing, pose.bow)
    }

    /// Top of the ears, in box coordinates (speech bubbles and z's start here).
    static func headTop(_ pose: PetPose) -> CGPoint {
        let r = rig(for: pose)
        return CGPoint(x: r.head.x + 3, y: r.head.y - 38)
    }

    /// Middle of the back, in box coordinates (the balloon string is tied here).
    static func backTop(_ pose: PetPose) -> CGPoint {
        let r = rig(for: pose)
        return CGPoint(x: r.body.x, y: r.body.y - r.bodySize.height / 2 + 3)
    }

    private static let pink = Color(hex: 0xFF8FAB)
    private static let ink = Color(hex: 0x2A1E2E)

    private var isDog: Bool { coat.species == .dog }

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / Self.box.width, y: size.height / Self.box.height)
            draw(ctx)
        }
        .shadow(color: .white.opacity(coat.dark ? 0.35 : 0), radius: 3)
    }

    private func draw(_ ctx: GraphicsContext) {
        let r = Self.rig(for: pose)
        let stride = pose.distance / 46 * 2 * .pi
        let swing: CGFloat = pose.walking ? 0.55 : 0
        let bob: CGFloat = pose.walking ? -abs(sin(stride)) * 2.2 : 0
        // Little paddling legs while floating down.
        let splay: CGFloat = pose.airborne ? 0.45 + CGFloat(sin(time * 7)) * 0.2 : 0
        let lying = pose.lie > 0.5
        let breathe = pose.walking ? 0 : CGFloat(sin(time * (lying ? 1.4 : 2.2))) * (lying ? 0.035 : 0.015)

        if pose.lift > -4 {
            let w = r.bodySize.width * 1.15
            ctx.fill(Path(ellipseIn: CGRect(x: r.body.x - w / 2, y: 99, width: w, height: 6)),
                     with: .color(.black.opacity(0.22)))
        }

        let near = coat.points ?? coat.fur
        let backAlpha = 1 - r.haunch
        // Far legs, then tail and body, then near legs over the body.
        leg(ctx, hip: r.backHip.moved(7, -1 + bob), length: r.backLength,
            angle: r.backAngle + sin(stride) * swing + splay, color: coat.shade, alpha: backAlpha)
        leg(ctx, hip: r.frontHip.moved(7, -1 + bob), length: r.frontLength,
            angle: r.frontAngle + sin(stride + .pi) * swing - splay, color: coat.shade)
        if isDog { dogTail(ctx, r, bob: bob) } else { catTail(ctx, r, bob: bob) }
        torso(ctx, r, bob: bob, breathe: breathe)
        if r.haunch > 0.01 { haunch(ctx, alpha: r.haunch) }
        leg(ctx, hip: r.backHip.moved(0, bob), length: r.backLength,
            angle: r.backAngle + sin(stride + .pi) * swing + splay, color: near, alpha: backAlpha)

        // The near front paw goes over the face when raised, and under the chin when lying.
        let raised = pose.pawUp
        let walkAngle = r.frontAngle + sin(stride) * swing - splay
        let frontAngle = walkAngle * (1 - raised) + pose.pawAngle * raised
        let frontLength = r.frontLength + 6 * raised
        let frontHip = mix(r.frontHip, r.head.moved(2, 19), pose.pawHigh * raised).moved(0, bob)
        let frontOnTop = raised > 0.4 || lying
        if !frontOnTop { leg(ctx, hip: frontHip, length: frontLength, angle: frontAngle, color: near) }
        head(ctx, r, bob: bob, stride: stride)
        if frontOnTop { leg(ctx, hip: frontHip, length: frontLength, angle: frontAngle, color: near) }
    }

    private func leg(_ ctx: GraphicsContext, hip: CGPoint, length: CGFloat, angle: CGFloat, color: Color,
                     alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        var c = ctx
        c.opacity = Double(alpha)
        c.translateBy(x: hip.x, y: hip.y)
        c.rotate(by: .radians(Double(angle)))
        c.fill(Path(roundedRect: CGRect(x: -6, y: -4, width: 12, height: length + 4), cornerRadius: 6),
               with: .color(color))
        c.fill(Path(ellipseIn: CGRect(x: -7, y: length - 4, width: 14, height: 8)), with: .color(coat.paw))
    }

    private func catTail(_ ctx: GraphicsContext, _ r: Rig, bob: CGFloat) {
        let pts = r.tail.map { $0.moved(0, bob) }
        var c = ctx
        let resting = pose.sit > 0.5 || pose.lie > 0.5
        let sway = pose.walking ? sin(time * 5.5) * 0.12
            : pose.bow > 0.5 ? sin(time * 9) * 0.15   // happy wag mid-stretch
            : sin(time * 2) * (resting ? 0.05 : 0.1)
        c.translateBy(x: pts[0].x, y: pts[0].y)
        c.rotate(by: .radians(sway))
        c.translateBy(x: -pts[0].x, y: -pts[0].y)
        var p = Path()
        p.move(to: pts[0])
        p.addCurve(to: pts[3], control1: pts[1], control2: pts[2])
        c.stroke(p, with: .color(coat.points ?? coat.fur), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        guard let tipColor = coat.stripes ?? (coat.points != nil ? coat.shade : coat.patches.last) else { return }
        // Last stretch of the curve in the tip colour.
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
            return CGPoint(x: a * pts[0].x + b * pts[1].x + d * pts[2].x + e * pts[3].x,
                           y: a * pts[0].y + b * pts[1].y + d * pts[2].y + e * pts[3].y)
        }
        var tip = Path()
        tip.move(to: point(0.85))
        tip.addLine(to: point(0.93))
        tip.addLine(to: pts[3])
        c.stroke(tip, with: .color(tipColor), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
    }

    /// Dogs wag fast whenever they're awake; the tail rises from the rump whatever the posture.
    private func dogTail(_ ctx: GraphicsContext, _ r: Rig, bob: CGFloat) {
        // Rump: the back end of the body ellipse, a little up.
        let back = CGPoint(x: -r.bodySize.width / 2 + 5, y: -r.bodySize.height * 0.18)
        let a = Double(r.bodyAngle)
        let base = CGPoint(x: r.body.x + back.x * CGFloat(cos(a)) - back.y * CGFloat(sin(a)),
                           y: r.body.y + bob + back.x * CGFloat(sin(a)) + back.y * CGFloat(cos(a)))
        let wag = pose.lie > 0.5 ? sin(time * 2) * 0.08 : sin(time * 14) * 0.32
        var c = ctx
        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(wag))
        let color = coat.fur
        switch coat.tail {
        case .plume:   // feathery, swept up and back, drooping at the end
            var p = Path()
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: -30, y: -6), control1: CGPoint(x: -10, y: -12), control2: CGPoint(x: -24, y: -18))
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            c.stroke(p, with: .color(coat.belly.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 4]))
        case .whip, .cat:   // up and back
            var p = Path()
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: -18, y: -30), control1: CGPoint(x: -12, y: -2), control2: CGPoint(x: -16, y: -18))
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            if coat.saddle != nil {   // beagle: white tip
                var tip = Path()
                tip.move(to: CGPoint(x: -17.5, y: -26))
                tip.addLine(to: CGPoint(x: -18, y: -30))
                c.stroke(tip, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
        case .curl:    // curled up over the back
            var p = Path()
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: 8, y: -12), control1: CGPoint(x: -16, y: -22), control2: CGPoint(x: 14, y: -32))
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            if let face = coat.face {
                c.stroke(p, with: .color(face.opacity(0.85)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
        case .stub:
            c.fill(Path(ellipseIn: CGRect(x: -9, y: -6, width: 12, height: 10)), with: .color(color))
        }
    }

    private func torso(_ ctx: GraphicsContext, _ r: Rig, bob: CGFloat, breathe: CGFloat) {
        var c = ctx
        c.translateBy(x: r.body.x, y: r.body.y + bob)
        c.rotate(by: .radians(Double(r.bodyAngle)))
        let w = r.bodySize.width, h = r.bodySize.height * (1 + breathe)
        let body = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        c.fill(body, with: .color(coat.fur))
        c.clip(to: body)
        if let saddle = coat.saddle {
            c.fill(Path(ellipseIn: CGRect(x: -w * 0.48, y: -h / 2 - 4, width: w * 0.72, height: h * 0.6)),
                   with: .color(saddle))
        }
        if coat.patches.count >= 2 {
            c.fill(Path(ellipseIn: CGRect(x: -w / 2 - 2, y: -h / 2 - 2, width: w * 0.42, height: h * 0.62)),
                   with: .color(coat.patches[1]))
            c.fill(Path(ellipseIn: CGRect(x: -w * 0.02, y: -h / 2 - 3, width: w * 0.34, height: h * 0.42)),
                   with: .color(coat.patches[0]))
        }
        c.fill(Path(ellipseIn: CGRect(x: -w * 0.18, y: h * 0.08, width: w * 0.56, height: h * 0.55)),
               with: .color(coat.belly))
        if let spots = coat.spots {
            for (fx, fy, d) in [(-0.32, -0.22, 7.0), (0.06, -0.3, 6.0), (0.28, -0.02, 5.0), (-0.12, 0.05, 6.5),
                                (-0.4, 0.12, 5.0), (0.16, -0.12, 4.0)] {
                c.fill(Path(ellipseIn: CGRect(x: w * fx - d / 2, y: h * fy - d / 2, width: d, height: d * 0.9)),
                       with: .color(spots))
            }
        }
        if let stripes = coat.stripes {
            for x in [-w * 0.24, -w * 0.06, w * 0.12] {
                var s = Path()
                s.move(to: CGPoint(x: x, y: -h / 2 - 3))
                s.addQuadCurve(to: CGPoint(x: x + 2, y: -h / 2 + 10), control: CGPoint(x: x + 5, y: -h / 2 + 4))
                c.stroke(s, with: .color(stripes), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
            }
        }
    }

    private func haunch(_ ctx: GraphicsContext, alpha: CGFloat) {
        var c = ctx
        c.opacity = Double(alpha)
        let thigh = Path(ellipseIn: CGRect(x: 32, y: 75, width: 36, height: 26))
        c.fill(thigh, with: .color(coat.fur))
        if let stripes = coat.stripes {
            var s = Path()
            s.move(to: CGPoint(x: 40, y: 80))
            s.addQuadCurve(to: CGPoint(x: 52, y: 78), control: CGPoint(x: 46, y: 76))
            c.stroke(s, with: .color(stripes), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
        if let spots = coat.spots {
            c.fill(Path(ellipseIn: CGRect(x: 42, y: 82, width: 6, height: 5.5)), with: .color(spots))
        }
        c.fill(Path(ellipseIn: CGRect(x: 59, y: 94, width: 14, height: 8)), with: .color(coat.paw))
    }

    private func head(_ ctx: GraphicsContext, _ r: Rig, bob: CGFloat, stride: CGFloat) {
        var c = ctx
        let hc = r.head.moved(0, bob)
        let idle: CGFloat = pose.walking || pose.airborne ? 0 : CGFloat(sin(time * 1.3)) * 0.04
        let neck = hc.moved(-6, 20)
        c.translateBy(x: neck.x, y: neck.y)
        c.rotate(by: .radians(Double(pose.headTilt + idle)))
        c.translateBy(x: -neck.x, y: -neck.y)

        // Upright ears sit behind the head; floppy and folded ones hang over it.
        if coat.ears == .pointy { pointyEars(c, hc) }

        let skull = isDog
            ? Path(ellipseIn: CGRect(x: hc.x - 28, y: hc.y - 24, width: 56, height: 48))
            : Path(ellipseIn: CGRect(x: hc.x - 27, y: hc.y - 25, width: 54, height: 50))
        c.fill(skull, with: .color(coat.fur))
        do {
            var marks = c
            marks.clip(to: skull)
            if let stripes = coat.stripes {
                for (dx, len) in [(-3.0, 7.0), (3.0, 9.5), (9.0, 7.0)] {
                    var s = Path()
                    s.move(to: hc.moved(CGFloat(dx), -27))
                    s.addLine(to: hc.moved(CGFloat(dx), -27 + CGFloat(len)))
                    marks.stroke(s, with: .color(stripes), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                }
            }
            if coat.patches.count >= 2 {
                marks.fill(Path(ellipseIn: CGRect(x: hc.x + 6, y: hc.y - 31, width: 28, height: 26)),
                           with: .color(coat.patches[0]))
                marks.fill(Path(ellipseIn: CGRect(x: hc.x - 33, y: hc.y - 26, width: 20, height: 18)),
                           with: .color(coat.patches[1]))
            }
            if let points = coat.points {
                marks.fill(Path(ellipseIn: CGRect(x: hc.x - 9, y: hc.y - 4, width: 24, height: 22)),
                           with: .color(points.opacity(0.6)))
            }
            if let face = coat.face {
                // Light cheeks and chin, with a blaze up between the eyes.
                marks.fill(Path(ellipseIn: CGRect(x: hc.x - 26, y: hc.y + 1, width: 58, height: 30)), with: .color(face))
                marks.fill(Path(ellipseIn: CGRect(x: hc.x - 1, y: hc.y - 14, width: 10, height: 22)), with: .color(face))
            }
            if let spots = coat.spots {
                for (dx, dy, d) in [(-15.0, -13.0, 5.5), (16.0, -16.0, 4.5), (-20.0, 4.0, 4.0)] {
                    marks.fill(Path(ellipseIn: CGRect(x: hc.x + CGFloat(dx), y: hc.y + CGFloat(dy), width: CGFloat(d), height: CGFloat(d))),
                               with: .color(spots))
                }
            }
        }

        if isDog { dogFace(c, hc) } else { catFace(c, hc) }

        switch coat.ears {
        case .pointy: break
        case .floppy: floppyEars(c, hc, stride: stride)
        case .folded: foldedEars(c, hc)
        }
    }

    private func eyes(_ c: GraphicsContext, _ centers: [CGPoint]) {
        let blinking = pose.eyes == .open && (time + 0.7).truncatingRemainder(dividingBy: 3.6) < 0.14
        for center in centers { eye(c, at: center, blinking: blinking) }
    }

    private func blush(_ c: GraphicsContext, _ hc: CGPoint, y: CGFloat) {
        for x in [hc.x - 21.5, hc.x + 14.5] {
            c.fill(Path(ellipseIn: CGRect(x: x, y: hc.y + y, width: 9, height: 5)), with: .color(Self.pink.opacity(0.55)))
        }
    }

    private func catFace(_ c: GraphicsContext, _ hc: CGPoint) {
        c.fill(Path(ellipseIn: CGRect(x: hc.x - 8, y: hc.y + 4, width: 22, height: 13)), with: .color(coat.muzzle))
        blush(c, hc, y: 5.5)
        eyes(c, [hc.moved(-7, 1), hc.moved(13, 1)])

        var nose = Path()
        nose.move(to: hc.moved(0.6, 7.3))
        nose.addLine(to: hc.moved(5.4, 7.3))
        nose.addLine(to: hc.moved(3, 10))
        nose.closeSubpath()
        c.fill(nose, with: .color(Self.pink))
        c.stroke(nose, with: .color(Self.pink), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

        if pose.mouthOpen > 0.05 {
            let h = 7.5 * pose.mouthOpen
            c.fill(Path(ellipseIn: CGRect(x: hc.x - 0.5, y: hc.y + 10.5, width: 7, height: h)), with: .color(Color(hex: 0x8C2F45)))
            c.fill(Path(ellipseIn: CGRect(x: hc.x + 0.5, y: hc.y + 10.5 + h * 0.55, width: 5, height: h * 0.4)),
                   with: .color(Self.pink))
        } else {
            var mouth = Path()   // the little "ω"
            mouth.move(to: hc.moved(3, 10))
            mouth.addQuadCurve(to: hc.moved(-1.2, 11), control: hc.moved(1.5, 13.8))
            mouth.move(to: hc.moved(3, 10))
            mouth.addQuadCurve(to: hc.moved(7.2, 11), control: hc.moved(4.5, 13.8))
            c.stroke(mouth, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            if pose.tongue {
                c.fill(Path(ellipseIn: CGRect(x: hc.x + 1.2, y: hc.y + 11.6, width: 3.8, height: 3.6)), with: .color(Self.pink))
            }
        }

        var whiskers = Path()
        for (y0, y1): (CGFloat, CGFloat) in [(9, 6), (11.5, 14)] {
            whiskers.move(to: hc.moved(-12, y0))
            whiskers.addLine(to: hc.moved(-28, y1))
            whiskers.move(to: hc.moved(18, y0))
            whiskers.addLine(to: hc.moved(34, y1))
        }
        c.stroke(whiskers, with: .color(coat.whisker.opacity(0.8)), lineWidth: 0.9)
    }

    private func dogFace(_ c: GraphicsContext, _ hc: CGPoint) {
        // Rounded snout with a big shiny nose.
        c.fill(Path(ellipseIn: CGRect(x: hc.x - 10, y: hc.y + 1, width: 28, height: 19)), with: .color(coat.muzzle))
        blush(c, hc, y: 6)
        eyes(c, [hc.moved(-9, -3), hc.moved(14, -3)])

        let noseColor = Color(hex: 0x231D26)
        c.fill(Path(roundedRect: CGRect(x: hc.x - 1.5, y: hc.y + 2, width: 11, height: 7.5), cornerRadius: 3.8),
               with: .color(noseColor))
        c.fill(Path(ellipseIn: CGRect(x: hc.x + 0.5, y: hc.y + 3, width: 3.4, height: 2)), with: .color(.white.opacity(0.85)))

        let lip = StrokeStyle(lineWidth: 1.4, lineCap: .round)
        if pose.mouthOpen > 0.05 {   // bark or yawn
            let h = 9 * pose.mouthOpen
            c.fill(Path(ellipseIn: CGRect(x: hc.x - 0.5, y: hc.y + 11, width: 10, height: h)), with: .color(Color(hex: 0x8C2F45)))
            c.fill(Path(ellipseIn: CGRect(x: hc.x + 1.5, y: hc.y + 11 + h * 0.5, width: 6, height: h * 0.45)),
                   with: .color(Self.pink))
        } else {
            var mouth = Path()
            mouth.move(to: hc.moved(4, 9.5))
            mouth.addLine(to: hc.moved(4, 12))
            mouth.addQuadCurve(to: hc.moved(-3, 12.5), control: hc.moved(0, 15))
            mouth.move(to: hc.moved(4, 12))
            mouth.addQuadCurve(to: hc.moved(11, 12.5), control: hc.moved(8, 15))
            c.stroke(mouth, with: .color(noseColor), style: lip)
            if pose.tongue || pose.eyes == .happy {   // happy panting
                let length = 8 + CGFloat(sin(time * 12)) * 1.2
                let tongue = Path(roundedRect: CGRect(x: hc.x + 1, y: hc.y + 12.5, width: 7, height: length), cornerRadius: 3.5)
                c.fill(tongue, with: .color(Color(hex: 0xFF7A9A)))
                var line = Path()
                line.move(to: hc.moved(4.5, 13.5))
                line.addLine(to: hc.moved(4.5, 12.5 + length * 0.6))
                c.stroke(line, with: .color(Color(hex: 0xE05A7E)), lineWidth: 1)
            }
        }
    }

    private func pointyEars(_ c: GraphicsContext, _ hc: CGPoint) {
        // Front ear twitches now and then.
        let twitch: CGFloat = time.truncatingRemainder(dividingBy: 4.3) < 0.15 ? 3 : 0
        let color = coat.points ?? coat.fur
        if isDog {
            let inner = coat.face ?? coat.belly
            ear(c, color: color, inner: inner, [hc.moved(-25, -6), hc.moved(-21, -40), hc.moved(-3, -22)])
            ear(c, color: color, inner: inner, [hc.moved(8, -23), hc.moved(27, -40 + twitch), hc.moved(29, -6)])
        } else {
            ear(c, color: color, inner: Self.pink, [hc.moved(-23, -10), hc.moved(-19, -36), hc.moved(-4, -23)])
            ear(c, color: coat.patches.first ?? color, inner: Self.pink,
                [hc.moved(9, -24), hc.moved(25, -36 + twitch), hc.moved(27, -9)])
        }
    }

    /// Long ears hanging at the sides of the head; they swing when walking and fly up when floating.
    private func floppyEars(_ c: GraphicsContext, _ hc: CGPoint, stride: CGFloat) {
        let flap: CGFloat = pose.airborne ? 1.0 + CGFloat(sin(time * 8)) * 0.15
            : pose.walking ? 0.15 + sin(stride * 2) * 0.18
            : CGFloat(sin(time * 1.7)) * 0.04 + pose.mouthOpen * 0.2
        let color = coat.earColor ?? coat.shade
        for side: CGFloat in [-1, 1] {
            let root = hc.moved(side < 0 ? -17 : 19, -19)
            var e = c
            e.translateBy(x: root.x, y: root.y)
            e.rotate(by: .radians(Double(-side * flap)))
            var p = Path()
            p.move(to: CGPoint(x: -side * 2, y: -3))
            p.addCurve(to: CGPoint(x: side * 9, y: 26), control1: CGPoint(x: side * 16, y: -6),
                       control2: CGPoint(x: side * 17, y: 22))
            p.addCurve(to: CGPoint(x: -side * 3, y: 6), control1: CGPoint(x: side * 1, y: 30),
                       control2: CGPoint(x: -side * 4, y: 18))
            p.closeSubpath()
            e.fill(p, with: .color(color))
        }
    }

    /// Small ears folded forward (pug).
    private func foldedEars(_ c: GraphicsContext, _ hc: CGPoint) {
        let color = coat.earColor ?? coat.shade
        for pts in [[hc.moved(-26, -14), hc.moved(-15, -26), hc.moved(-9, -15)],
                    [hc.moved(15, -25), hc.moved(29, -15), hc.moved(19, -9)]] {
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            c.fill(p, with: .color(color))
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        }
    }

    private func eye(_ c: GraphicsContext, at p: CGPoint, blinking: Bool) {
        let line = StrokeStyle(lineWidth: 2.2, lineCap: .round)
        if blinking {
            c.fill(Path(roundedRect: CGRect(x: p.x - 5, y: p.y - 0.9, width: 10, height: 1.8), cornerRadius: 0.9),
                   with: .color(Self.ink))
            return
        }
        switch pose.eyes {
        case .happy:   // ^ ^
            var a = Path()
            a.move(to: p.moved(-4.6, 1.8))
            a.addQuadCurve(to: p.moved(4.6, 1.8), control: p.moved(0, -5))
            c.stroke(a, with: .color(Self.ink), style: line)
        case .closed:  // sleepy ‿
            var a = Path()
            a.move(to: p.moved(-4.6, 0))
            a.addQuadCurve(to: p.moved(4.6, 0), control: p.moved(0, 4.6))
            c.stroke(a, with: .color(Self.ink), style: line)
        case .open:
            let g = CGPoint(x: pose.gaze.x * 1.6, y: pose.gaze.y * 1.6)
            let whites = CGRect(x: p.x - 5.25, y: p.y - 6.25, width: 10.5, height: 12.5)
            if let iris = coat.iris {
                c.fill(Path(ellipseIn: whites), with: .color(iris))
                c.fill(Path(ellipseIn: CGRect(x: p.x - 3 + g.x, y: p.y - 4.4 + g.y, width: 6, height: 8.8)),
                       with: .color(Self.ink))
            } else {
                c.fill(Path(ellipseIn: whites), with: .color(Self.ink))
            }
            // Two sparkles make the eyes look big and shiny.
            c.fill(Path(ellipseIn: CGRect(x: p.x - 3.4 + g.x, y: p.y - 4.8 + g.y, width: 4, height: 4)), with: .color(.white))
            c.fill(Path(ellipseIn: CGRect(x: p.x + 1.2 + g.x, y: p.y + 1.6 + g.y, width: 1.8, height: 1.8)),
                   with: .color(.white.opacity(0.9)))
        }
    }

    private func ear(_ ctx: GraphicsContext, color: Color, inner: Color, _ pts: [CGPoint]) {
        var o = Path()
        o.addLines(pts)
        o.closeSubpath()
        ctx.fill(o, with: .color(color))
        ctx.stroke(o, with: .color(color), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        let cx = (pts[0].x + pts[1].x + pts[2].x) / 3, cy = (pts[0].y + pts[1].y + pts[2].y) / 3
        var i = Path()
        i.addLines(pts.map { CGPoint(x: cx + ($0.x - cx) * 0.55, y: cy + ($0.y - cy) * 0.55 + 1.5) })
        i.closeSubpath()
        ctx.fill(i, with: .color(inner))
        ctx.stroke(i, with: .color(inner), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
}

// MARK: - Speech bubble

struct SpeechBubble: View {
    let text: String
    /// Horizontal offset of the tail from the bubble's centre, so it points at the pet's head.
    let tailOffset: CGFloat

    private static let fill = Color(hex: 0xFFFDF8)

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.navyTop)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.fill))
            .overlay {
                GeometryReader { g in
                    let limit = g.size.width / 2 - 22
                    BubbleTail()
                        .fill(Self.fill)
                        .frame(width: 18, height: 10)
                        .position(x: g.size.width / 2 + min(max(tailOffset, -limit), limit), y: g.size.height + 4.5)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
