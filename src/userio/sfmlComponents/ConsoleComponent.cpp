#include "ConsoleComponent.h"
#include "../../simulator.h"

namespace BS
{
    ConsoleComponent::ConsoleComponent()
    {
        this->console = tgui::TextArea::create();
        this->console->setReadOnly(true);
        this->console->setTextSize(static_cast<unsigned>(13 * p.uiScale));
        this->console->setSize("20%", "25%");
        this->console->setPosition("80%", "75%");
    }

    ConsoleComponent::~ConsoleComponent(){}

    void ConsoleComponent::log(std::string message)
    {
        this->logMessages.push_back(tgui::String(message));
        if (this->logMessages.size() > 100)
        {
            this->logMessages.erase(this->logMessages.begin());
        }
        this->console->setText(tgui::String::join(this->logMessages, "\n"));
    }
}