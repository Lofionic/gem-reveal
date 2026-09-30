import Observation

@Observable
final class ViewModel {
    private(set) var gemViewModels: [GemDefinition: RevealViewModel]
    
    var gemReveal: RevealViewModel?
    
    init() {
        gemViewModels = GemDefinition.allCases.reduce(into: [:]) {
            $0[$1] = .init(gemDefinition: $1)
        }
    }
    
    func openGem(_ gemDefinition: GemDefinition) {
        gemReveal = gemViewModels[gemDefinition]
    }
    
    func closeGem() {
        gemReveal = nil
    }
    
    func resetAll() {
        gemViewModels.values.forEach {
            $0.unlockDate = nil
        }
    }
}
