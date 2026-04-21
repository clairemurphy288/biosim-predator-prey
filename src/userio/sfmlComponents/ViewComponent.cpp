#include "ViewComponent.h"

namespace BS
{
    ViewComponent::ViewComponent(sf::Vector2u windowSize)
    {
        this->windowWidth = windowSize.x;
        this->windowHeight = windowSize.y;
        this->view = new sf::View(sf::FloatRect(
            sf::Vector2f(0.f, 0.f),
            sf::Vector2f(static_cast<float>(this->windowWidth), static_cast<float>(this->windowHeight))));
            }

    ViewComponent::~ViewComponent()
    {
    }

    // Pan/zoom disabled — view is fixed to match the simulation grid.
    void ViewComponent::updateInput(const sf::Event &, sf::RenderWindow *)
    {
    }

    void ViewComponent::lock()
    {
        this->isLocked = true;
    }

    void ViewComponent::unlock()
    {
        this->isLocked = false;
    }

    void ViewComponent::resize(sf::Vector2u newSize)
    {
        this->windowWidth = newSize.x;
        this->windowHeight = newSize.y;
        this->view->setSize(sf::Vector2f(newSize.x, newSize.y));
        this->view->setCenter(sf::Vector2f(newSize.x / 2.f, newSize.y / 2.f));
            }
}
