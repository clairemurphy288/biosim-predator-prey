#ifndef INDIV_H_INCLUDED
#define INDIV_H_INCLUDED

// Indiv is the structure that represents one individual agent.

#include <SFML/Graphics.hpp>

#include <algorithm>
#include <cstdint>
#include <array>
#include "../basicTypes.h"
#include "./genome-neurons.h"
#include <cereal/archives/json.hpp>
#include <cereal/types/vector.hpp>

namespace BS {

// Also see class Peeps.

enum class AgentType : uint8_t { PREY = 0, PREDATOR = 1 };

struct Indiv {
    bool alive;
    uint16_t index; // index into peeps[] container
    Coord loc;   // refers to a location in grid[][]
    Coord birthLoc;
    unsigned age;
    AgentType type = AgentType::PREY;
    Genome genome;
    NeuralNet nnet;   // derived from .genome
    float responsiveness;  // 0.0..1.0 (0 is like asleep)
    unsigned oscPeriod; // 2..4*p.stepsPerGeneration (TBD, see executeActions())
    unsigned longProbeDist; // distance for long forward probe for obstructions
    Dir lastMoveDir;  // direction of last movement
    unsigned challengeBits; // modified when the indiv accomplishes some task
    unsigned captures = 0; // predator-prey: number of prey captured this generation
    std::array<float, Action::NUM_ACTIONS> feedForward(unsigned simStep); // reads sensors, returns actions
    float getSensor(Sensor, unsigned simStep) const;
    void initialize(uint16_t index, Coord loc, Genome &&genome, AgentType type);
    void createWiringFromGenome(); // creates .nnet member from .genome member
    std::stringstream printNeuralNet() const;
    std::stringstream printIGraphEdgeList() const;
    void printGenome() const;

	sf::CircleShape shape;
    uint8_t makeGeneticColor();
    void fillColor();
    void initVariables();

    template <class Archive>
    void serialize(Archive &ar)
    {
        ar(index, CEREAL_NVP(loc), CEREAL_NVP(genome), CEREAL_NVP(type));
    }
};

} // end namespace BS

#endif // INDIV_H_INCLUDED
