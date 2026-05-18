#ifndef PARAMS_H_INCLUDED
#define PARAMS_H_INCLUDED

// Global simulator parameters

#include <string>
#include <cstdint>
#include <ctime>
#include <utility>
#include <vector>

// To add a new parameter:
//    1. Add a member to struct Params in params.h.
//    2. Add a member and its default value to privParams in ParamManager::setDefault()
//          in params.cpp.
//    3. Add an else clause to ParamManager::ingestParameter() in params.cpp.
//    4. Add a line to the user's parameter file (default name biosim4.ini)

namespace BS {

enum class RunMode { STOP, RUN, PAUSE, ABORT, LOAD, RESTART };
extern RunMode runMode;

// A private copy of Params is initialized by ParamManager::init(), then modified by
// UI events by ParamManager::uiMonitor(). The main simulator thread can get an
// updated, read-only, stable snapshot of Params with ParamManager::paramsSnapshot.

struct Params {
    unsigned population; // >= 0
    unsigned stepsPerGeneration; // > 0
    unsigned maxGenerations; // >= 0
    unsigned numThreads; // > 0
    unsigned signalLayers; // >= 0
    unsigned genomeMaxLength; // > 0
    unsigned maxNumberNeurons; // > 0
    double pointMutationRate; // 0.0..1.0
    double geneInsertionDeletionRate; // 0.0..1.0
    double deletionRatio; // 0.0..1.0
    bool killEnable;
    bool sexualReproduction;
    bool chooseParentsByFitness;
    float populationSensorRadius; // > 0.0
    unsigned signalSensorRadius; // > 0
    float responsiveness; // >= 0.0
    unsigned responsivenessCurveKFactor; // 1, 2, 3, or 4
    unsigned longProbeDistance; // > 0
    unsigned shortProbeBarrierDistance; // > 0
    float valenceSaturationMag;
    bool saveVideo;
    unsigned videoStride; // > 0
    unsigned videoSaveFirstFrames; // >= 0, overrides videoStride
    unsigned videoFps; // > 0, playback frame rate
    unsigned displayScale;
    float uiScale; // 1.0 or 1.5 - scales window size and display
    unsigned agentSize;
    unsigned genomeAnalysisStride; // > 0
    unsigned displaySampleGenomes; // >= 0
    unsigned genomeComparisonMethod; // 0 = Jaro-Winkler; 1 = Hamming
    bool updateGraphLog;
    unsigned updateGraphLogStride; // > 0
    unsigned challenge;
    unsigned barrierType; // >= 0
    bool deterministic;
    unsigned RNGSeed; // >= 0
    bool autoSave;
    unsigned autoSavePredatorNetsPerGeneration; // >= 0
    unsigned autoSavePreyNetsPerGeneration; // >= 0
    unsigned autoSaveNetEpochs; // >= 0, 0 disables
    unsigned autoSaveNetStride; // >= 1, save every N generations

    // Predator-prey (coevolution) settings.
    // predatorPreyEnabled is now decoupled from `challenge`: enable it to
    // overlay the predator-prey dynamic on top of ANY arena/challenge.
    // When enabled:
    //   - The population is split into predators / prey by predatorFraction
    //   - Predators reproduce based on captures (the challenge is ignored
    //     for them; they live in whatever arena is active)
    //   - Prey reproduce based on the active challenge's survival criterion
    //     (so e.g. challenge=Circle becomes "prey must reach the circle and
    //     evade predators")
    bool predatorPreyEnabled;
    double predatorFraction; // 0.0..1.0  (initial / fixed-mode fraction)
    unsigned predatorMinCapturesToReproduce; // >= 0
    unsigned predatorCaptureNorm; // > 0 (captures needed for score==1.0)
    float predatorPreyPerceptionRadius; // > 0 (radius for predator/prey sensors)
    // Movement speed knobs.  Each agent only evaluates its neural net and
    // executes actions every N simSteps (1 = full speed, 2 = half speed,
    // 3 = third speed, ...).  Age, starvation, and other passive timers
    // still tick every step, so a slower predator simply has fewer chances
    // to act per generation.
    unsigned predatorActionPeriod;       // >= 1
    unsigned preyActionPeriod;           // >= 1

    // Predator-prey dynamics extensions (added for Lotka-Volterra style oscillations).
    // - predatorRatioMode = 0  : fixed.  Each generation always spawns
    //   round(predatorFraction * population) predators.  This is the original
    //   biosim4 behaviour and damps out any population oscillation.
    // - predatorRatioMode = 1  : proportional.  The next generation's predator
    //   fraction is driven by the relative fitness of the two species in the
    //   just-finished generation:
    //       frac = (predScore^gain) / (predScore^gain + preyScore^gain)
    //   clamped to [predatorRatioFloor, predatorRatioCeil] to prevent collapse.
    unsigned predatorRatioMode;          // 0 = fixed, 1 = proportional
    double   predatorRatioFloor;         // 0.0..1.0 (must be < ceil)
    double   predatorRatioCeil;          // 0.0..1.0 (must be > floor)
    double   predatorRatioGain;          // >=1 sharpens response, <1 dampens
    // Predator within-generation death.  If a predator goes more than
    // predatorStarvationSteps simSteps without a capture (after a grace period
    // at gen start), it is queued for death.  Set to 0 to disable starvation.
    unsigned predatorStarvationSteps;    // 0 disables
    unsigned predatorStarvationGrace;    // simSteps at start of gen with no starvation
    // Prey selection pressure: only the top X by age get to reproduce.  At 1.0
    // every surviving prey reproduces (original behaviour).
    double   preyTopFractionToReproduce; // 0.0..1.0

    // These must not change after initialization
    uint16_t sizeX; // 2..0x10000
    uint16_t sizeY; // 2..0x10000
    unsigned genomeInitialLengthMin; // > 0 and < genomeInitialLengthMax
    unsigned genomeInitialLengthMax; // > 0 and < genomeInitialLengthMin
    std::string logDir;
    std::string imageDir;
    std::string graphLogUpdateCommand;

    // These are updated automatically and not set via the parameter file
    unsigned parameterChangeGenerationNumber; // the most recent generation number that an automatic parameter change occured at

    template <class Archive>
    void serialize(Archive &ar)
    {
        ar(challenge, pointMutationRate, barrierType);
    }
};

class ParamManager {
public:
    const Params &getParamRef() const { return privParams; } // for public read-only access
    void setDefaults();
    void registerConfigFile(const char *filename);
    void updateFromConfigFile(unsigned generationNumber);
    void checkParameters();

    void setPopulation(unsigned population);
    void changeFromUi(std::string name, std::string val);
    void updateFromUi();

    void updateFromSave(Params params_);
private:
    Params privParams;
    std::string configFilename;
    time_t lastModTime; // when config file was last read
    void ingestParameter(std::string name, std::string val);

    std::vector<std::pair<std::string, std::string>> paramsFromUI;
};

// Returns a copy of params with default values overridden by the values
// in the specified config file. The filename of the config file is saved
// inside the params for future reference.
Params paramsInit(int argc, char **argv);

} // end namespace BS

#endif // PARAMS_H_INCLUDED
