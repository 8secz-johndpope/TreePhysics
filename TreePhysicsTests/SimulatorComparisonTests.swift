import XCTest
@testable import TreePhysics
import simd

class SimulatorComparisonTests: XCTestCase {
    var device: MTLDevice!, commandQueue: MTLCommandQueue!
    var compositeBodiesBuffer, jointsBuffer, rigidBodiesBuffer: MTLBuffer!

    var cpuSimulator: Simulator!
    var metalSimulator: MetalSimulator!
    var expecteds: [RigidBody]!

    var attractorField: AttractorField!

    var debug: KernelDebugger!

    override func setUp() {
        super.setUp()
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!

        let root = RigidBody(length: 0, radius: 0, density: 0, kind: .static)
        let rigidBodyPen = RigidBodyPen(parent: root)
        let rule = Rewriter.Rule(symbol: "A", replacement: #"[!"&FFFA]/////[!"&FFFA]/////[!"&FFFA]"#)
        let lSystem = Rewriter.rewrite(premise: "A", rules: [rule], generations: 1)
        let configuration = Interpreter<RigidBodyPen>.Configuration(
            randomScale: 0.4,
            angle: 18 * .pi / 180,
            thickness: 0.002*0.002*Float.pi,
            thicknessScale: 0.9,
            stepSize: 0.1,
            stepSizeScale: 0.9)
        let interpreter = Interpreter(configuration: configuration, pen: rigidBodyPen)
        interpreter.interpret(lSystem)

        let tree = Tree(root)
        self.attractorField = AttractorField()

        self.cpuSimulator = Simulator(tree: tree)
        cpuSimulator.add(field: attractorField)
        self.metalSimulator = MetalSimulator(device: device, root: root)
        metalSimulator.add(field: attractorField)

        attractorField.position = float3(0.1, 0.1, 0.1)

        self.debug = KernelDebugger(device: device, count: metalSimulator.rigidBodies.count, maxChars: 8192, label: "metal")
    }

    func testUpdate() {
        let expect = expectation(description: "wait")
        tick(2, expect)
        waitForExpectations(timeout: 10, handler: {error in})
    }

    func tick(_ n: Int, _ expect: XCTestExpectation) {
        guard n > 0 else { expect.fulfill(); return }

        let captureManager = MTLCaptureManager.shared()
        captureManager.startCapture(device: device)
        print(captureManager.isCapturing)

        let commandBuffer = commandQueue.makeCommandBuffer()!

        cpuSimulator.update(at: 1.0 / 60)
        metalSimulator.encode(commandBuffer: debug.wrap(commandBuffer), at: 1.0 / 60)
        commandBuffer.addCompletedHandler { _ in
            self.debug.print()
            let metalSimulator = self.metalSimulator!

            let rigidBodies = UnsafeMutableRawPointer(metalSimulator.rigidBodiesBuffer.contents()).bindMemory(to: RigidBodyStruct.self, capacity: metalSimulator.rigidBodies.count)
            let compositeBodies = UnsafeMutableRawPointer(metalSimulator.compositeBodiesBuffer.contents()).bindMemory(to: CompositeBodyStruct.self, capacity: metalSimulator.rigidBodies.count)
            let joints = UnsafeMutableRawPointer(metalSimulator.jointsBuffer.contents()).bindMemory(to: JointStruct.self, capacity: metalSimulator.rigidBodies.count)

            for i in 0..<(metalSimulator.rigidBodies.count-1) {
                let message = "iteration[\(i)]"
                XCTAssertEqual(rigidBodies[i].force, metalSimulator.rigidBodies[i].force, accuracy: 0.00001, message)
                XCTAssertEqual(rigidBodies[i].torque, metalSimulator.rigidBodies[i].torque, accuracy: 0.00001, message)

                XCTAssertEqual(compositeBodies[i].force,  metalSimulator.rigidBodies[i].composite.force, accuracy: 0.00001, message)
                XCTAssertEqual(compositeBodies[i].torque, metalSimulator.rigidBodies[i].composite.torque, accuracy: 0.00001, message)

                XCTAssertEqual(joints[i].θ,  metalSimulator.rigidBodies[i].parentJoint!.θ, accuracy: 0.0001, message)

                XCTAssertEqual(rigidBodies[i].position, metalSimulator.rigidBodies[i].position, accuracy: 0.0001, message)
                XCTAssertEqual(rigidBodies[i].centerOfMass, metalSimulator.rigidBodies[i].centerOfMass, accuracy: 0.0001, message)
                XCTAssertEqual(rigidBodies[i].inertiaTensor, metalSimulator.rigidBodies[i].inertiaTensor, accuracy: 0.00001, message)
            }

            self.tick(n - 1, expect)
        }

        commandBuffer.commit()
        captureManager.stopCapture()
    }
}
