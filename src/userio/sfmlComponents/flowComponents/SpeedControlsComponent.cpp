#include "SpeedControlsComponent.h"
#include "../../../simulator.h"

namespace BS
{
    SpeedControlsComponent::SpeedControlsComponent(tgui::Widget::Ptr positionReferenceComponent_, tgui::Container::Ptr container_, const float controlOffset_)
    {
        this->positionReferenceWidget = positionReferenceComponent_;
        this->container = container_;
        this->controlOffset = controlOffset_;
    }

    /**
     * Initializes the speed controls for the right panel component.
     *
     * @param min The minimum value for the speed controls.
     * @param max The maximum value for the speed controls.
     * @param initValue The initial value for the speed controls.
     * @param changeSpeedCallback A callback function that is called when the value of the speed controls changes.
     *
     * @throws None.
     */
    void SpeedControlsComponent::init(int min, int max, int initValue, std::function<void(float value)> changeSpeedCallback)
    {
        tgui::Slider::Ptr speedSlider = tgui::Slider::create();
        speedSlider->setMinimum(min);
        speedSlider->setMaximum(max);
        speedSlider->setStep(1);
        speedSlider->setValue(initValue);
        speedSlider->setPosition({"5%", bindBottom(this->positionReferenceWidget) + this->controlOffset});
        speedSlider->setSize("90%", 16.f * p.uiScale);
        speedSlider->onValueChange([changeSpeedCallback](float value) {
            changeSpeedCallback(value);
        });
        this->container->add(speedSlider, "SpeedSlider");

        this->labelReferenceWidget = speedSlider;
    }

    tgui::Widget::Ptr SpeedControlsComponent::getLabelReferenceWidget()
    {
        return this->labelReferenceWidget;
    }
}