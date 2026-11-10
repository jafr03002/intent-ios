import IntentDesign
import MetalKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The live light behind the top of the dashboard and the calendar: a Metal port of
/// the web's WebGL shader (DashboardWash.tsx), line for line. Slow shafts fall from
/// above the screen, a caustic teal pool drifts like light through water and a film
/// grain removes gradient banding. The light gathers over `sunX` (today's column on
/// the dashboard, the selected day's on the calendar) and glides when that changes.
/// A finger pulls the light towards it and a tap sends a soft ripple out.
///
/// The shader is compiled from source at runtime: xtool builds on Linux, which has
/// no Metal compiler, so a `.metal` file can't ship. Compiling takes a few ms once.
/// If Metal is unavailable or the compile fails, only the static gradient underneath
/// (the web's `.sessions-wash` fallback) shows - the same as a lost WebGL context.
///
/// Cost: one full-screen triangle at 1.2 px per point (the web renders at 0.6x the
/// device pixel ratio, capped at 2x), about 21 value-noise lookups per pixel. That is
/// light work for any A-series GPU; it stops drawing while scrolled off screen, while
/// the app is in the background, and draws one still frame under Reduce Motion.
struct LiveWash: View {
    /// 0...1 across the wash; nil = today's column on the Monday-first week arc.
    var sunX: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var live = false

    var body: some View {
        ZStack {
            StaticWash()
            if WashRenderer.shared != nil {
                WashMetalView(sunX: sunX.map(Float.init), reduceMotion: reduceMotion) { live = true }
                    .opacity(live ? 1 : 0)
                    .animation(.easeOut(duration: 1), value: live)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `.sessions-wash`: grey at the top fading into black with the teal pool on top.
private struct StaticWash: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0x2f / 255, green: 0x35 / 255, blue: 0x38 / 255), location: 0),
                    .init(color: Color(red: 0x1b / 255, green: 0x22 / 255, blue: 0x24 / 255), location: 0.38),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
            // radial-gradient(75% 60% at 50% 18%, rgb(214 222 222 / 0.22), transparent 72%)
            EllipticalGradient(
                colors: [Color(red: 214 / 255, green: 222 / 255, blue: 222 / 255).opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: 0.18), startRadiusFraction: 0, endRadiusFraction: 0.5)
            // radial-gradient(60% 55% at 50% 30%, cyan / 0.3, transparent 70%)
            EllipticalGradient(
                colors: [Color.intent.sessionsCyan.opacity(0.3), .clear],
                center: UnitPoint(x: 0.5, y: 0.3), startRadiusFraction: 0, endRadiusFraction: 0.42)
        }
    }
}

// MARK: - SwiftUI bridge

private struct WashMetalView: UIViewRepresentable {
    var sunX: Float?
    var reduceMotion: Bool
    var onFirstFrame: () -> Void

    func makeUIView(context: Context) -> WashMTKView {
        let view = WashMTKView(renderer: WashRenderer.shared!)
        view.onFirstFrame = onFirstFrame
        view.sunXTarget = sunX
        view.reduceMotion = reduceMotion
        return view
    }

    func updateUIView(_ view: WashMTKView, context: Context) {
        view.onFirstFrame = onFirstFrame
        view.sunXTarget = sunX
        view.reduceMotion = reduceMotion
    }
}

// MARK: - Renderer (one device, one pipeline for the whole app)

@MainActor
final class WashRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    /// nil when there is no Metal device or the shader fails to compile.
    static let shared: WashRenderer? = WashRenderer()

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            appLog.error("wash: no Metal device")
            return nil
        }
        do {
            let library = try device.makeLibrary(source: washShaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "wash_vertex")
            desc.fragmentFunction = library.makeFunction(name: "wash_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            appLog.error("wash: shader build failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        self.device = device
        self.queue = queue
    }
}

/// Matches `struct Uniforms` in the shader: five float4s, no padding surprises.
private struct WashUniforms {
    var frame: SIMD4<Float>   // res.x, res.y, time, sunX
    var cyan: SIMD4<Float>
    var mist: SIMD4<Float>
    var pointer: SIMD4<Float> // x, y (0..1, y down), strength
    var ripple: SIMD4<Float>  // x, y, age in seconds, strength
}

// MARK: - The view

final class WashMTKView: MTKView {
    private let renderer: WashRenderer
    var onFirstFrame: (() -> Void)?
    private var drawnOnce = false

    var sunXTarget: Float? {
        didSet {
            // The first target is where the light starts; later ones glide.
            if !drawnOnce, let target = sunXTarget { sunX = target; pointer.x = target; pointer.tx = target }
            if reduceMotion, oldValue != sunXTarget { setNeedsDisplay() }
        }
    }

    var reduceMotion = false {
        didSet {
            guard oldValue != reduceMotion || !configured else { return }
            configured = true
            // Reduce Motion: one still frame per change, no pointer.
            isPaused = reduceMotion
            enableSetNeedsDisplay = reduceMotion
            touchTracker?.isEnabled = !reduceMotion
            setNeedsDisplay()
        }
    }
    private var configured = false

    // Same state as the web's draw loop.
    private let start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var sunX: Float = WashMTKView.todayColumnX()
    private var pointer = (x: Float(0.5), y: Float(0.33), s: Float(0), tx: Float(0.5), ty: Float(0.33), ts: Float(0), down: false)
    private var ripple = (x: Float(0.5), y: Float(0.3), start: CACurrentMediaTime() - 100, s: Float(0))
    private let cyan: SIMD4<Float>
    private var touchTracker: WashTouchTracker?

    init(renderer: WashRenderer) {
        self.renderer = renderer
        // The accent comes from the token, so the light follows the palette.
        var r: CGFloat = 0.378, g: CGFloat = 0.876, b: CGFloat = 0.942, a: CGFloat = 1
        UIColor(Color.intent.sessionsCyan).getRed(&r, green: &g, blue: &b, alpha: &a)
        cyan = SIMD4(Float(r), Float(g), Float(b), 1)
        super.init(frame: .zero, device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isOpaque = true
        backgroundColor = .black
        preferredFramesPerSecond = 60
        isUserInteractionEnabled = false
        let base = sunXTarget ?? Self.todayColumnX()
        sunX = base
        pointer.x = base
        pointer.tx = base
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Today's column on the Monday-first week arc, as a 0..1 x position.
    static func todayColumnX() -> Float {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date()) // 1 = Sunday
        let mondayFirst = (weekday + 5) % 7
        return (Float(mondayFirst) + 0.5) / 7
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The light is all soft gradients, so it renders below device resolution.
        if let window {
            contentScaleFactor = min(window.screen.scale, 2) * 0.6
        }
        // Like the web's passive window listeners: the tracker sees every touch on
        // the window but never claims one, so taps and scrolling are untouched.
        touchTracker?.view?.removeGestureRecognizer(touchTracker!)
        touchTracker = nil
        if let window {
            let tracker = WashTouchTracker()
            tracker.onEvent = { [weak self] event, location in self?.handleTouch(event, at: location) }
            tracker.isEnabled = !reduceMotion
            window.addGestureRecognizer(tracker)
            touchTracker = tracker
        }
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if reduceMotion { setNeedsDisplay() }
    }

    private func handleTouch(_ event: WashTouchTracker.Event, at location: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let local = convert(location, from: nil)
        let x = Float(local.x / bounds.width)
        let y = Float(local.y / bounds.height)
        switch event {
        case .down:
            guard x >= 0, x <= 1, y >= 0, y <= 1 else { return }
            pointer.down = true
            pointer.tx = x
            pointer.ty = y
            pointer.ts = 1
            ripple = (x, y, CACurrentMediaTime(), 1)
        case .move:
            guard pointer.down else { return }
            pointer.tx = x
            pointer.ty = max(-0.1, min(1.1, y))
        case .up:
            pointer.down = false
            pointer.ts = 0
        }
    }

    /// Off screen (scrolled away, or under another tab): skip the frame.
    private var isOnScreen: Bool {
        guard let window, !isHidden else { return false }
        return convert(bounds, to: nil).intersects(window.bounds)
    }

    override func draw(_ rect: CGRect) {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, now - last))
        last = now
        guard isOnScreen || reduceMotion,
              let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = renderer.queue.makeCommandBuffer() else { return }

        let t = reduceMotion ? 12 : Float(now - start) + 40
        let ease = 1 - exp(-dt * 7)
        pointer.x += (pointer.tx - pointer.x) * ease
        pointer.y += (pointer.ty - pointer.y) * ease
        pointer.s += (pointer.ts - pointer.s) * (1 - exp(-dt * (pointer.ts > pointer.s ? 6 : 1.6)))
        let base = sunXTarget ?? Self.todayColumnX()
        let sunTarget = base + (pointer.x - base) * 0.4 * pointer.s
        // Reduced motion draws one still frame per change, so it can't glide there.
        sunX = reduceMotion ? sunTarget : sunX + (sunTarget - sunX) * (1 - exp(-dt * 2.5))

        let size = drawableSize
        var u = WashUniforms(
            frame: SIMD4(Float(size.width), Float(size.height), t, sunX),
            cyan: cyan,
            mist: SIMD4(214 / 255, 222 / 255, 222 / 255, 1),
            pointer: SIMD4(pointer.x, pointer.y, pointer.s, 0),
            ripple: SIMD4(ripple.x, ripple.y, Float(now - ripple.start), ripple.s))

        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<WashUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        if !drawnOnce {
            drawnOnce = true
            let callback = onFirstFrame
            DispatchQueue.main.async { callback?() }
        }
    }
}

/// Sees every touch on the window without ever recognising, so it can't delay,
/// cancel or block anything (it recognises alongside everything, never instead).
private final class WashTouchTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    enum Event { case down, move, up }
    var onEvent: ((Event, CGPoint) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onEvent?(.down, touch.location(in: nil)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onEvent?(.move, touch.location(in: nil)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onEvent?(.up, touch.location(in: nil)) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onEvent?(.up, .zero)
        state = .failed
    }

    override func reset() {
        super.reset()
        onEvent?(.up, .zero)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Shader (DashboardWash.tsx's FRAG, in Metal)

/// Differences from the GLSL are mechanical: Metal's fragment position is top-down,
/// so `uv.y` needs no flip; `atan(y, x)` is `atan2`; and `pow` of a negative base is
/// undefined in Metal, so the ripple's square is written out.
private let washShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 frame;   // res.xy, time, sunX
    float4 cyan;
    float4 mist;
    float4 pointer; // xy (0..1, y down), z = strength
    float4 ripple;  // xy, age in seconds, strength
};

struct VOut { float4 pos [[position]]; };

vertex VOut wash_vertex(uint vid [[vertex_id]]) {
    const float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VOut o;
    o.pos = float4(corners[vid], 0.0, 1.0);
    return o;
}

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1.0, 0.0)), u.x),
               mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    const float2x2 r = float2x2(float2(0.8, -0.6), float2(0.6, 0.8));
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = r * p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

fragment float4 wash_fragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 res = u.frame.xy;
    float t = u.frame.z;
    float sunX = u.frame.w;
    float3 cyan = u.cyan.rgb;
    float3 mist = u.mist.rgb;

    float2 frag = in.pos.xy;
    float2 uv = frag / res;
    float aspect = res.x / res.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y);

    // A tap's ripple: a thin ring that pushes the light outwards as it grows.
    float2 rp = float2((u.ripple.x - 0.5) * aspect, u.ripple.y);
    float2 rv = p - rp;
    float rd = length(rv);
    float ringR = u.ripple.z * 0.75;
    float rk = (rd - ringR) * 16.0;
    float ring = exp(-(rk * rk)) * u.ripple.w * exp(-u.ripple.z * 1.8);
    p += (rv / max(rd, 1e-3)) * ring * 0.035;

    // The old CSS wash, kept as the ground: grey at the top, into black.
    float3 col = mix(float3(0.184, 0.208, 0.220), float3(0.106, 0.133, 0.141), smoothstep(0.0, 0.38, uv.y));
    col = mix(col, float3(0.0), smoothstep(0.38, 1.0, uv.y));

    // Shafts from a source above the screen, over today's column.
    float2 sp = float2((sunX - 0.5) * aspect, -0.32);
    float2 d = p - sp;
    float ang = atan2(d.x, d.y);
    float dist = length(d);
    float shafts = 0.6 * fbm(float2(ang * 7.0, t * 0.07)) + 0.4 * noise(float2(ang * 19.0 - t * 0.05, t * 0.09));
    shafts = smoothstep(0.4, 0.82, shafts);
    float cone = exp(-ang * ang * 2.6);
    float fall = exp(-dist * 1.5);
    float3 shaftCol = mix(mist, cyan, smoothstep(0.35, 0.95, dist));
    col += shaftCol * shafts * cone * fall * 0.36;

    // The teal pool behind the arc, domain-warped so it moves like water light.
    float2 q = p * 1.7;
    float2 w = float2(fbm(q + float2(0.0, t * 0.05)), fbm(q + float2(5.2, -t * 0.04)));
    float f = fbm(q + 1.9 * w + float2(t * 0.03, 0.0));
    float2 bc = float2((sunX - 0.5) * aspect * 0.85, 0.33);
    float2 bd = (p - bc) * float2(0.85, 1.35);
    float pool = exp(-dot(bd, bd) * 3.4);
    col += cyan * pool * (0.1 + 0.4 * f * f);

    // Caustics: thin bright ridges of warped noise, only inside the pool.
    float c = fbm(q * 2.2 + 2.4 * w + float2(-t * 0.06, t * 0.04));
    float caustic = pow(max(1.0 - abs(c * 2.0 - 1.0), 0.0), 9.0);
    col += mix(cyan, mist, 0.5) * caustic * pool * 0.16;
    // A brighter core right behind today's circle.
    col += mix(mist, cyan, 0.4) * exp(-dot(bd, bd) * 22.0) * 0.1;

    // The finger's light: a soft lens that also lifts the caustics under it.
    float2 pp = float2((u.pointer.x - 0.5) * aspect, u.pointer.y);
    float2 pd = p - pp;
    float lens = exp(-dot(pd, pd) * 10.0) * u.pointer.z;
    col += mix(cyan, mist, 0.3) * lens * (0.14 + 0.46 * f);
    col += mix(cyan, mist, 0.5) * caustic * lens * 0.15;
    col += cyan * ring * 0.35;

    // Fade the added light out well before the cards start.
    col *= 1.0 - smoothstep(0.55, 1.0, uv.y) * 0.85;
    col = 1.0 - exp(-col * 1.12);

    // Film grain, also the dither that keeps the long gradients from banding.
    col += (hash(frag + fract(t * 7.0) * 91.0) - 0.5) * (2.2 / 255.0);
    return float4(col, 1.0);
}
"""
