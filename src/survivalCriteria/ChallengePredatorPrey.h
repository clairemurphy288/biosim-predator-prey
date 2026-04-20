#ifndef CHALLENGE_PREDATOR_PREY_H_INCLUDED
#define CHALLENGE_PREDATOR_PREY_H_INCLUDED

#include "SurvivalCriteria.h"

namespace BS
{
    class ChallengePredatorPrey : public SurvivalCriteria
    {
    public:
        ChallengePredatorPrey();
        std::pair<bool, float> passed(const Indiv &indiv, const Params &p, Grid &grid) override;
    };
}

#endif

