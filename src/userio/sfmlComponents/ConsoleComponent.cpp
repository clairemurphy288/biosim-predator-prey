#include "ConsoleComponent.h"
#include "../../simulator.h"

namespace BS
{
    ConsoleComponent::ConsoleComponent()
    {
        this->console = tgui::TextArea::create();
        this->console->setReadOnly(true);
        this->console->setTextSize(static_cast<unsigned>(11 * p.uiScale));
        this->console->setSize("100%", "100%");
        this->console->setPosition("0%", "0%");
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