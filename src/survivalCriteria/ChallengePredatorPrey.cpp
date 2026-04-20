#include "ChallengePredatorPrey.h"

namespace BS
{
    ChallengePredatorPrey::ChallengePredatorPrey()
        : SurvivalCriteria(
              CHALLENGE_PREDATOR_PREY,
              "Predator-Prey",
              "Two coevolving types: predators reproduce via captures, prey via survival time.\n"
              "Set predatorFraction, predatorMinCapturesToReproduce, predatorCaptureNorm in the ini.")
    {
    }

    // Note: true coevolution (separate predator/prey parent pools) is handled in spawnNewGeneration().
    std::pair<bool, float> ChallengePredatorPrey::passed(const Indiv &indiv, const Params &p, Grid &)
    {
        if (!indiv.alive) {
            return {false, 0.f};
        }

        if (indiv.type == AgentType::PREDATOR)
        {
            const bool passed = indiv.captures >= p.predatorMinCapturesToReproduce;
            const float score = std::min(1.f, indiv.captures / static_cast<float>(p.predatorCaptureNorm));
            return {passed, score};
        }
        else
        {
            const float score = std::min(1.f, indiv.age / static_cast<float>(p.stepsPerGeneration));
            return {true, score};
        }
    }
}

