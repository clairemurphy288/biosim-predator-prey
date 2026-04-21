#ifndef BOTTOMBUTTONSCOMPONENT_H_INCLUDED
#define BOTTOMBUTTONSCOMPONENT_H_INCLUDED

#include <TGUI/TGUI.hpp>
#include <string>
#include <vector>

namespace BS
{
    /**
     * Populates the action section of the right panel with save/load/restart and
     * individual-inspection controls.
     */
    class BottomButtonsComponent
    {
    public:
        BottomButtonsComponent(
            tgui::Container::Ptr container,
            std::function<void(void)> saveCallback,
            std::function<void(void)> loadCallback,
            std::function<void(bool)> restartCallback,
            std::function<void()> saveIndivCallback,
            std::function<void(std::string name, std::string val)> changeSettingsCallback,
            std::function<void()> indivInfoCallback,
            std::function<void(bool)> selectPassedCallback);

        void flushRestartButton();
        void switchPassedSelection(bool selected);

    private:
        tgui::Container::Ptr container;
        tgui::ToggleButton::Ptr restartButton;
        tgui::Button::Ptr selectPassedBtn;
        bool isSelectPassed = false;
        std::function<void(bool)> selectPassedCallback;
    };
}
#endif
