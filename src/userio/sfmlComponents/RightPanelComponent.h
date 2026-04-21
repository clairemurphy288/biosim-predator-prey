#ifndef LEFTPANEL_H_INCLUDED
#define LEFTPANEL_H_INCLUDED

#include <TGUI/TGUI.hpp>
#include <TGUI/Backend/SFML-Graphics.hpp>
#include "./settingsComponents/ChallengeBoxComponent.h"
#include "./settingsComponents/BarrierBoxComponent.h"

namespace BS
{
    /**
     * Populates the scrollable settings section of the right panel.
     */
    class RightPanelComponent
    {
    public:
        RightPanelComponent(
            tgui::Container::Ptr container,
            int panelWidth,
            std::function<void(std::string name, std::string val)> changeSettingsCallback,
            std::function<void()> infoCallback,
            std::function<void(float)> scaleChangedCallback
        );
        ~RightPanelComponent();

        void setFromParams();

    private:
        float labelOffset;
        float controlOffset;
        float widgetHeight;
        float widgetWidth;

        tgui::Container::Ptr container;

        ChallengeBoxComponent *challengeBoxComponent;
        BarrierBoxComponent *barrierBoxComponent;
        tgui::EditBox::Ptr mutationRateEditBox;
        tgui::EditBox::Ptr populationEditBox;
        tgui::EditBox::Ptr stepsPerGenerationEditBox;
        tgui::EditBox::Ptr predatorFractionEditBox;
        tgui::EditBox::Ptr predatorMinCapturesEditBox;
        tgui::EditBox::Ptr predatorCaptureNormEditBox;

        std::function<void(std::string name, std::string val)> changeSettingsCallback;

        tgui::EditBox::Ptr createEditBox(tgui::Widget::Ptr reference, tgui::String text, std::string labelName, std::string settingsName);
        void createLabel(tgui::Widget::Ptr widget, const tgui::String &text);
        void initSettingsComponents(std::function<void()> infoCallback, std::function<void(float)> scaleChangedCallback);
    };
}

#endif
