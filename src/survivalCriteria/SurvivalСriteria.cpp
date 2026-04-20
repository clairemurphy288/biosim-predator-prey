#include <cassert>
#include <utility>

#include "SurvivalCriteria.h"

namespace BS
{
    /**
     * Overridable function for creating shapes of survival criteria
     */
    void SurvivalCriteria::initShapes(int liveDisplayScale)
    {
    }

    /**
     * Overridable function that called at the end of each step.
     * Some criterias like ChallengeRadioactiveWalls has special logic
     * performed after each step. Most of criterias do nothing.
     */
    void SurvivalCriteria::endOfStep(unsigned simStep, const Params &p, Grid &grid, Peeps &peeps) 
    {
    }

    /**
     * Clears all Drawables of survival criteria
     * 
     */
    void SurvivalCriteria::deleteShapes()
    {
        for (sf::Drawable *shape : this->shapes)
        {
            delete shape;
        }
        this->shapes.clear();
    }

    void SurvivalCriteria::createCircle(float radius, float x, float y)
    {
        sf::CircleShape* shape = new sf::CircleShape();
        shape->setRadius(radius);
        shape->setPosition(sf::Vector2f(x, y));
        shape->setOutlineThickness(1.f);
        shape->setOutlineColor(this->defaultColor);
        shape->setFillColor(sf::Color::Transparent);
        this->shapes.push_back(shape);
    }

    void SurvivalCriteria::createBorder(float size, int liveDisplayScale)
    {
        //create border around grid
        sf::Color borderColor = sf::Color::Black;
        sf::RectangleShape* topRect = new sf::RectangleShape();
        topRect->setSize(sf::Vector2f(p.sizeX * liveDisplayScale + size*2, size));
        topRect->setPosition(sf::Vector2f(0.f - size, 0.f - size));
        topRect->setFillColor(borderColor);
        this->shapes.push_back(topRect);

        sf::RectangleShape* bottomRect = new sf::RectangleShape();
        bottomRect->setSize(sf::Vector2f(p.sizeX * liveDisplayScale + size*2, size));
        bottomRect->setPosition(sf::Vector2f(0.f - size, static_cast<float>(p.sizeY * liveDisplayScale)));
        bottomRect->setFillColor(borderColor);
        this->shapes.push_back(bottomRect);

        sf::RectangleShape* leftRect = new sf::RectangleShape();
        leftRect->setSize(sf::Vector2f(size, p.sizeY * liveDisplayScale + size*2));
        leftRect->setPosition(sf::Vector2f(0.f - size, 0.f - size));
        leftRect->setFillColor(borderColor);
        this->shapes.push_back(leftRect);

        sf::RectangleShape* rightRect = new sf::RectangleShape();
        rightRect->setSize(sf::Vector2f(size, p.sizeY * liveDisplayScale + size*2));
        rightRect->setPosition(sf::Vector2f(static_cast<float>(p.sizeX * liveDisplayScale), 0.f - size));
        rightRect->setFillColor(borderColor);
        this->shapes.push_back(rightRect);
    }

    void SurvivalCriteria::createLine(sf::Vector2f vectorOne, sf::Vector2f vectorTwo)
    {
        sf::VertexArray* lineLeft = new sf::VertexArray(sf::PrimitiveType::LineStrip, 2);
        (*lineLeft)[0].position = vectorOne;
        (*lineLeft)[0].color = this->defaultColor;
        (*lineLeft)[1].position = vectorTwo;
        (*lineLeft)[1].color = this->defaultColor;
        this->shapes.push_back(lineLeft);
    }
}
