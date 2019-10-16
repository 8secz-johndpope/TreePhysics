import AppKit
import SceneKit
import PlaygroundSupport
import ModelIO
import SceneKit.ModelIO
@testable import TreePhysics

var config = AutoTree.Config()
config.internodeLength = 0.1
config.occupationRadius = config.internodeLength * 1
config.perceptionRadius = config.internodeLength * 5
config.apicalDominance = 0.5
config.baseRadius = 0.1
config.extremityRadius = 0.001
config.sensitivityOfBudsToLight = 3

config.branchGravitropismBias = 0.7
config.branchStraightnessBias = 0.1

config.maxShootLength = 5
config.gravitropismAngle = .pi/2
config.branchingAngle = .pi/5
config.phyllotacticAngle = .pi/4
config.fullExposure = 1
config.shadowDecayFactor = 0.5
config.shadowIntensity = 0.1
config.shadowDepth = 10
config.initialShadowGridSize = 256

// FIXME using squares
// FIXME test ev
// FIXME rename variables
// FIXME ensure sp/sv max at 1, otherwise vertical internodes are starved
config.sp = 1/3
config.sv = 1

let autoTree = AutoTree(config)

let (root, _) = autoTree.seedling()
let shadowGrid = AutoTree.ArrayBackedShadowGrid(config)
let simulator = autoTree.growthSimulator(shadowGrid: shadowGrid)
simulator.addRoot(root)

var enableAllBuds = true

if !enableAllBuds {
    let url = Bundle.main.url(forResource: "ARFaceGeometry", withExtension: "obj", subdirectory: "art.scnassets")!
    let asset = MDLAsset(url: url)
    let mdlMesh = asset.object(at: 0) as! MDLMesh

    let face = SCNNode(mdlObject: mdlMesh)
    let scale: Float = 0.1
    let offset = SIMD3<Float>(0,1,-0.1)
    face.simdScale = SIMD3<Float>(repeating: 1) * scale
    face.simdPosition = offset

    let vertices: [SIMD3<Float>] = mdlMesh.vertices.map { $0 * scale + offset }
    simulator.addAttractionPoints(vertices)
}

func draw(_ node: AutoTree.Node) -> SCNNode {
    let result = SCNNode()
    switch node {
    case let p as AutoTree.Parent:
        if let n = p.mainChild {
            let g = draw(n)
            result.addChildNode(g)
        }
        if let n = p.lateralChild {
            let g = draw(n)
            result.addChildNode(g)
        }
        let k = createAxesNode(quiverLength: 0.2, quiverThickness: 0.3)
        k.simdOrientation = node.orientation
        k.simdPosition = node.position

        let l = createAxesNode(quiverLength: 0.1, quiverThickness: 0.6)
        l.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: normalize(p.orientation.vertical))
        l.simdPosition = node.position
        result.addChildNode(k)
        result.addChildNode(l)
    default: ()
    }
    return result
}

extension AutoTree.GrowthSimulator: Playable {
    public func update() -> SCNNode? {
        do {
            try simulator.update(enableAllBuds: enableAllBuds)
            let pen = CylinderPen<UInt32>(radialSegmentCount: 15, parent: nil)
            pen.start(at: root.position, orientation: root.orientation, thickness: config.baseRadius)
            autoTree.draw(root, pen: pen, showBuds: false)
            return pen.node()
        } catch AutoTree.Error.noAttractionPoints {
            print("No attraction points")
            enableAllBuds = true
        } catch AutoTree.Error.noSelectedBuds {
            print("No selected buds; Try fiddling with the config.perceptionRadius and config.perceptionAngle")
            enableAllBuds = true
        } catch AutoTree.Error.noVigor {
            print("Try fiddling with config.fullExposure and config.shadowIntensity")
            enableAllBuds = true
        } catch {
            print("Error", error)
        }
        return nil
    }

    public func inspect() -> SCNNode? {
//        let plot = Plot<UInt32>()
//        plot.scatter(points: Array(simulator.attractionPoints), scale: config.internodeLength)
//        plot.voxels(data: shadowGrid.storage, size: shadowGrid.size, scale: config.internodeLength)
//        return plot.node()
        return draw(root)
    }
}

try! simulator.update(enableAllBuds: enableAllBuds)
let viewController = PlayerViewController(frame: CGRect(x:0 , y:0, width: 640, height: 480))
viewController.playable = simulator
PlaygroundPage.current.liveView = viewController


let id: simd_quatf = simd_quatf(angle: 1, axis: .zero)
let horizontal = simd_quatf(from: SIMD3<Float>(0,1,0), to: SIMD3<Float>(0,0,1))

print(acos(Float(1)))
