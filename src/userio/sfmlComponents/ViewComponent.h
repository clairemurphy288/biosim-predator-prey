#ifndef SFMLVIEW_H_INCLUDED
#define SFMLVIEW_H_INCLUDED

#include <SFML/Graphics.hpp>
#include <SFML/System.hpp>

namespace BS
{
    class ViewComponent
    {
    public:
        ViewComponent(sf::Vector2u windowSize);
        ~ViewComponent();
        sf::View* getView() { return this->view; }
        void updateInput(const sf::Event &e, sf::RenderWindow* window);
        void lock();
        void unlock();
        void resize(sf::Vector2u newSize);
    private:
        sf::View* view;
        int windowWidth;
        int windowHeight;
        bool isLocked = false;
    };
}

#endif // SFMLVIEW_H_INCLUDED
