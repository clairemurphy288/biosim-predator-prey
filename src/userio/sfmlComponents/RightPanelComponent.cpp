#include "RightPanelComponent.h"
#include "../../simulator.h"

namespace BS
{
    RightPanelComponent::RightPanelComponent(
        tgui::Container::Ptr container_,
        int panelWidth,
        std::function<void(std::string name, std::string val)> changeSettingsCallback_,
        std::function<void()> infoCallback,
        std::function<void(float)> scaleChangedCallback
    )
    {
        this->container = container_;
        this->changeSettingsCallback = changeSettingsCallback_;
        this->labelOffset  = 13.f * p.uiScale;
        this->controlOffset = 22.f * p.uiScale;
        this->widgetHeight  = 22.f * p.uiScale;
        // Leave room for the scrollbar on the right side
        this->widgetWidth   = panelWidth - static_cast<int>(36.f * p.uiScale);

        this->initSettingsComponents(infoCallback, scaleChangedCallback);
    }

    void RightPanelComponent::initSettingsComponents(std::function<void()> infoCallback, std::function<void(float)> scaleChangedCallback)
    {
        float s = p.uiScale;

        // Challenge box
        this->challengeBoxComponent = new ChallengeBoxComponent([this](std::string name, std::string val) {
            this->changeSettingsCallback(name, val);
        });
        tgui::ComboBox::Ptr challengeBox = this->challengeBoxComponent->getComboBox();
        challengeBox->setPosition({10.f * s, 10.f * s});
        challengeBox->setSize(this->widgetWidth, this->widgetHeight);
        this->container->add(challengeBox, "ChallengeBox");
        this->createLabel(challengeBox, "Challenge");

        tgui::Button::Ptr challengeInfoBtn = tgui::Button::create("i");
        challengeInfoBtn->setPosition({bindRight(challengeBox) + 4.f * s, bindTop(challengeBox)});
        challengeInfoBtn->setSize(this->widgetHeight, this->widgetHeight);
        challengeInfoBtn->onPress([infoCallback]() { infoCallback(); });
        this->container->add(challengeInfoBtn, "ChallengeInfoBtn");

        // Mutation rate
        this->mutationRateEditBox = this->createEditBox(challengeBox, tgui::String(p.pointMutationRate), "Mutation Rate", "pointmutationrate");

        // Barrier box
        this->barrierBoxComponent = new BarrierBoxComponent([this](std::string name, std::string val) {
            this->changeSettingsCallback(name, val);
        });
        tgui::ComboBox::Ptr barrierBox = this->barrierBoxComponent->getComboBox();
        barrierBox->setPosition({bindLeft(this->mutationRateEditBox), bindBottom(this->mutationRateEditBox) + this->controlOffset});
        barrierBox->setSize(this->widgetWidth, this->widgetHeight);
        this->container->add(barrierBox, "BarrierBox");
        this->createLabel(barrierBox, "Barrier");

        // Population
        this->populationEditBox = this->createEditBox(barrierBox, tgui::String(p.population), "Population", "population");

        // Steps per generation
        this->stepsPerGenerationEditBox = this->createEditBox(this->populationEditBox, tgui::String(p.stepsPerGeneration), "Steps Per Generation", "stepspergeneration");

        // Kill enabled
        float checkH = 14.f * s;
        tgui::CheckBox::Ptr killBox = tgui::CheckBox::create();
        killBox->setSize(checkH, checkH);
        killBox->setPosition({bindLeft(this->stepsPerGenerationEditBox), bindBottom(this->stepsPerGenerationEditBox) + this->controlOffset});
        killBox->setText("Kill enabled");
        killBox->setChecked(p.killEnable);
        killBox->onChange([this](bool checked) {
            this->changeSettingsCallback("killenable", checked ? "true" : "false");
        });
        this->container->add(killBox, "KillBox");

        // Predator-prey params
        this->predatorFractionEditBox      = this->createEditBox(killBox, tgui::String(p.predatorFraction), "Predator fraction", "predatorfraction");
        this->predatorMinCapturesEditBox   = this->createEditBox(this->predatorFractionEditBox, tgui::String(p.predatorMinCapturesToReproduce), "Min captures (predators)", "predatormincapturestoreproduce");
        this->predatorCaptureNormEditBox   = this->createEditBox(this->predatorMinCapturesEditBox, tgui::String(p.predatorCaptureNorm), "Capture norm (predators)", "predatorcapturenorm");
    }

    tgui::EditBox::Ptr RightPanelComponent::createEditBox(tgui::Widget::Ptr reference, tgui::String text, std::string labelName, std::string settingsName)
    {
        tgui::EditBox::Ptr editBox = tgui::EditBox::create();
        editBox->setPosition({bindLeft(reference), bindBottom(reference) + this->controlOffset});
        editBox->setSize(this->widgetWidth, this->widgetHeight);
        editBox->setText(text);
        editBox->onReturnKeyPress([this, settingsName, editBox](const tgui::String &val) {
            this->changeSettingsCallback(settingsName, val.toStdString());
        });
        this->container->add(editBox);
        this->createLabel(editBox, labelName);
        return editBox;
    }

    void RightPanelComponent::createLabel(tgui::Widget::Ptr widget, const tgui::String &text)
    {
        tgui::Label::Ptr label = tgui::Label::create(text);
        label->setPosition({bindLeft(widget), bindTop(widget) - this->labelOffset});
        this->container->add(label);
    }

    void RightPanelComponent::setFromParams()
    {
        this->challengeBoxComponent->setFromParams();
        this->mutationRateEditBox->setText(tgui::String(p.pointMutationRate));
        if (this->predatorFractionEditBox)
            this->predatorFractionEditBox->setText(tgui::String(p.predatorFraction));
        if (this->predatorMinCapturesEditBox)
            this->predatorMinCapturesEditBox->setText(tgui::String(p.predatorMinCapturesToReproduce));
        if (this->predatorCaptureNormEditBox)
            this->predatorCaptureNormEditBox->setText(tgui::String(p.predatorCaptureNorm));
    }

    RightPanelComponent::~RightPanelComponent()
    {
    }
}
