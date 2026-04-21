#include "FlowControlComponent.h"
#include "../../../simulator.h"

namespace BS
{
    FlowControlComponent::FlowControlComponent(
        tgui::Container::Ptr container_,
        int speedMin,
        int speedMax,
        int speedInitValue,
        std::function<void(float value)> changeSpeedCallback,
        std::function<void(bool)> pauseCallback_,
        std::function<void(bool, bool)> stopAtSmthCallback_
    )
    {
        this->container = container_;
        this->pauseCallback = pauseCallback_;
        this->stopAtSmthCallback = stopAtSmthCallback_;

        float s = p.uiScale;

        // ── Row 1: play/pause icon + generation progress bar ──────────────
        this->pausePicture = tgui::Picture::create("Resources/Pictures/play.png");
        this->pausePicture->onClick([this]() { this->pauseResume(); });
        float picW = this->pausePicture->getSize().x * s;
        float picH = this->pausePicture->getSize().y * s;
        this->pausePicture->setSize(picW, picH);
        this->pausePicture->setPosition(10.f * s, 10.f * s);
        this->container->add(this->pausePicture, "PlayPause");

        this->generationProgressBar = tgui::ProgressBar::create();
        this->generationProgressBar->setMinimum(0);
        float barH = picH * 0.55f;
        this->generationProgressBar->setSize("75%", barH);
        this->generationProgressBar->setPosition(
            {bindRight(this->pausePicture) + 8.f * s,
             bindTop(this->pausePicture) + (picH - barH) / 2.f});
        this->container->add(this->generationProgressBar, "GenProgressBar");

        // ── Row 2: speed slider ────────────────────────────────────────────
        tgui::Slider::Ptr speedSlider = tgui::Slider::create();
        speedSlider->setMinimum(speedMin);
        speedSlider->setMaximum(speedMax);
        speedSlider->setStep(1);
        speedSlider->setValue(speedInitValue);
        speedSlider->setPosition({10.f * s, "52%"});
        speedSlider->setSize("90%", 14.f * s);
        speedSlider->onValueChange([changeSpeedCallback](float v) { changeSpeedCallback(v); });
        this->container->add(speedSlider, "SpeedSlider");

        tgui::Label::Ptr speedLabel = tgui::Label::create("Speed");
        speedLabel->setPosition({bindLeft(speedSlider), bindTop(speedSlider) - 14.f * s});
        this->container->add(speedLabel, "SpeedLabel");

        // ── Row 3 & 4: pause-at checkboxes ────────────────────────────────
        float checkH = 14.f * s;
        this->stopAtStartButton = tgui::CheckBox::create("Pause at gen start");
        this->stopAtStartButton->setSize(checkH, checkH);
        this->stopAtStartButton->setPosition({bindLeft(speedSlider), bindBottom(speedSlider) + 10.f * s});
        this->stopAtStartButton->onChange([this](bool checked) {
            if (checked) {
                this->stopAtSmthCallback(true, false);
                this->stopAtEndButton->setChecked(false);
            } else {
                this->stopAtSmthCallback(false, this->stopAtEndButton->isChecked());
            }
        });
        this->container->add(this->stopAtStartButton, "PauseAtStart");

        this->stopAtEndButton = tgui::CheckBox::create("Pause at gen end");
        this->stopAtEndButton->setSize(checkH, checkH);
        this->stopAtEndButton->setPosition({bindLeft(this->stopAtStartButton), bindBottom(this->stopAtStartButton) + 5.f * s});
        this->stopAtEndButton->onChange([this](bool checked) {
            if (checked) {
                this->stopAtSmthCallback(false, true);
                this->stopAtStartButton->setChecked(false);
            } else {
                this->stopAtSmthCallback(this->stopAtStartButton->isChecked(), false);
            }
        });
        this->container->add(this->stopAtEndButton, "PauseAtEnd");
    }

    FlowControlComponent::~FlowControlComponent() {}

    void FlowControlComponent::pauseResume()
    {
        this->pauseResume(!this->paused);
    }

    void FlowControlComponent::pauseResume(bool paused)
    {
        this->paused = paused;
        if (this->paused || this->externalPause)
            this->pausePicture->getRenderer()->setTexture("Resources/Pictures/pause.png");
        else
            this->pausePicture->getRenderer()->setTexture("Resources/Pictures/play.png");
        this->pauseCallback(this->paused || this->externalPause);
    }

    void FlowControlComponent::pauseExternal(bool paused)
    {
        this->externalPause = paused;
        this->pauseResume(this->paused);
    }

    void FlowControlComponent::startNewGeneration(unsigned generation, unsigned stepsPerGeneration)
    {
        this->generationProgressBar->setMaximum(stepsPerGeneration);
    }

    void FlowControlComponent::endOfStep(unsigned simStep)
    {
        this->generationProgressBar->setValue(simStep);
    }

    void FlowControlComponent::flushStopAtSmthButtons()
    {
        this->stopAtStartButton->setChecked(false);
        this->stopAtEndButton->setChecked(false);
    }
}
