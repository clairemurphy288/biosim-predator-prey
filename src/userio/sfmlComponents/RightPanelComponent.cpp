#include "RightPanelComponent.h"
#include "../../simulator.h"

namespace BS
{
    /**
     * Constructor
     * @param windowSize Size of the window
     * @param changeSettingsCallback Callback for changing settings
     * @param infoCallback Callback for showing informational child window
     */
    RightPanelComponent::RightPanelComponent(
        sf::Vector2u windowSize,
        std::function<void(std::string name, std::string val)> changeSettingsCallback_,
        std::function<void()> infoCallback,
        std::function<void(float)> scaleChangedCallback
    )
    {
        this->changeSettingsCallback = changeSettingsCallback_;
        this->labelOffset = 15.f * p.uiScale;
        this->controlOffset = 20.f * p.uiScale;
        this->widgetHeight = 24.f * p.uiScale;
        this->widgetWidth = 150.f * p.uiScale;

        // create panel
        this->panel = tgui::Panel::create();
        this->panel->setSize("20%", windowSize.y);
        this->panel->setAutoLayout(tgui::AutoLayout::Right);

        this->initSettingsComponents(infoCallback, scaleChangedCallback);
    }

    /**
     * Initializes values of settings components and places int on the pannel
     */
    void RightPanelComponent::initSettingsComponents(std::function<void()> infoCallback, std::function<void(float)> scaleChangedCallback)
    {
        // setup UI scale combo box
        /** 
        tgui::ComboBox::Ptr scaleBox = tgui::ComboBox::create();
        scaleBox->addItem("1x", "1.0");
        scaleBox->addItem("1.5x", "1.5");
        if (p.uiScale >= 1.5f)
            scaleBox->setSelectedItemById("1.5");
        else
            scaleBox->setSelectedItemById("1.0");
        scaleBox->setPosition("5%", "15%");
        scaleBox->onItemSelect([scaleChangedCallback](const tgui::String&, const tgui::String& id) {
            float scale = std::stof(id.toStdString());
            scaleChangedCallback(scale);
        });
        this->panel->add(scaleBox, "ScaleBox");
        this->createLabel(scaleBox, "UI Scale");*/

        // setup challenge box
        this->challengeBoxComponent = new ChallengeBoxComponent([this](std::string name, std::string val) {
            this->changeSettingsCallback(name, val);
        });
        tgui::ComboBox::Ptr challengeBox = this->challengeBoxComponent->getComboBox();
        challengeBox->setPosition({"5%", "15%"}); //bindBottom(scaleBox) + this->controlOffset});
        challengeBox->setSize(this->widgetWidth, this->widgetHeight);
        this->panel->add(challengeBox, "ChallengeBox");
        this->createLabel(challengeBox, "Challenge");

        tgui::Button::Ptr challengeInfoBtn = tgui::Button::create("i");
        challengeInfoBtn->setPosition({bindRight(challengeBox) + 5.f * p.uiScale, bindTop(challengeBox)});
        challengeInfoBtn->onPress([infoCallback]() { 
            infoCallback(); 
        });
        challengeInfoBtn->setSize(this->widgetHeight, this->widgetHeight);
        this->panel->add(challengeInfoBtn, "IndivInfoBtn");

        // setup mutation rate
        this->mutationRateEditBox = this->createEditBox(challengeBox, tgui::String(p.pointMutationRate), "Mutation Rate");
        this->createConfirmButton(this->mutationRateEditBox, "pointmutationrate", "MutationButton");        
        
        // setup barrier box
        this->barrierBoxComponent = new BarrierBoxComponent([this](std::string name, std::string val) {
            this->changeSettingsCallback(name, val); 
        });
        tgui::ComboBox::Ptr barrierBox = this->barrierBoxComponent->getComboBox();
        barrierBox->setPosition({bindLeft(this->mutationRateEditBox), bindBottom(this->mutationRateEditBox) + this->controlOffset});
        barrierBox->setSize(this->widgetWidth, this->widgetHeight);
        this->panel->add(barrierBox, "BarrierBox");
        this->createLabel(barrierBox, "Barrier");

        // setup population
        this->populationEditBox = this->createEditBox(this->barrierBoxComponent->getComboBox(), tgui::String(p.population), "Population");
        this->createConfirmButton(this->populationEditBox, "population", "PopulationButton");

        // setup steps per generation
        this->stepsPerGenerationEditBox = this->createEditBox(this->populationEditBox, tgui::String(p.stepsPerGeneration), "Steps Per Generation");
        this->createConfirmButton(this->stepsPerGenerationEditBox, "stepspergeneration", "StepsPerGenerationButton");

        tgui::CheckBox::Ptr killBox = tgui::CheckBox::create();
        float checkboxSize = 16.f * p.uiScale;
        killBox->setSize(checkboxSize, checkboxSize);
        killBox->setPosition({bindLeft(this->stepsPerGenerationEditBox), bindBottom(this->stepsPerGenerationEditBox) + this->controlOffset});
        killBox->setText("Kill enabled");
        killBox->setChecked(p.killEnable);
        killBox->onChange([this](bool checked) { 
            this->changeSettingsCallback("killenable", checked ? "true" : "false");
        });
        this->panel->add(killBox, "KillBox");

        // Predator-prey params (used by challenge = CHALLENGE_PREDATOR_PREY)
        this->predatorFractionEditBox = this->createEditBox(killBox, tgui::String(p.predatorFraction), "Predator fraction");
        this->createConfirmButton(this->predatorFractionEditBox, "predatorfraction", "PredatorFractionButton");

        this->predatorMinCapturesEditBox = this->createEditBox(this->predatorFractionEditBox, tgui::String(p.predatorMinCapturesToReproduce), "Min captures (predators)");
        this->createConfirmButton(this->predatorMinCapturesEditBox, "predatormincapturestoreproduce", "PredatorMinCapturesButton");

        this->predatorCaptureNormEditBox = this->createEditBox(this->predatorMinCapturesEditBox, tgui::String(p.predatorCaptureNorm), "Capture norm (predators)");
        this->createConfirmButton(this->predatorCaptureNormEditBox, "predatorcapturenorm", "PredatorCaptureNormButton");
    }

    /**
     * Creates simple edit box with label
     */
    tgui::EditBox::Ptr RightPanelComponent::createEditBox(tgui::Widget::Ptr reference, tgui::String text, std::string name)
    {
        tgui::EditBox::Ptr editBox = tgui::EditBox::create();
        editBox->setPosition({bindLeft(reference), bindBottom(reference) + this->controlOffset});
        editBox->setSize(this->widgetWidth, this->widgetHeight);
        editBox->setText(text);
        this->panel->add(editBox);
        this->createLabel(editBox, name);
        return editBox;
    }

    /**
     * Creates confirm button
     */
    void RightPanelComponent::createConfirmButton(tgui::EditBox::Ptr editBox, std::string settingsName, std::string name)
    {
        tgui::Button::Ptr button = tgui::Button::create("Ok");
        button->setPosition({bindRight(editBox) + 2.f * p.uiScale, bindTop(editBox)});
        button->onPress([this, settingsName, editBox]() {
            this->changeSettingsCallback(settingsName, editBox->getText().toStdString());
        });
        button->setSize(40.f * p.uiScale, editBox->getSize().y);
        this->panel->add(button, name);
    }

    /**
     * Updates values of settings components from Params
     */
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

    /**
     * Creates label
     */
    void RightPanelComponent::createLabel(tgui::Widget::Ptr widget, const tgui::String &text)
    {
        tgui::Label::Ptr label = tgui::Label::create(text);
        label->setPosition({bindLeft(widget), bindTop(widget) - this->labelOffset});
        this->panel->add(label);
    }

    RightPanelComponent::~RightPanelComponent()
    {
    }

    /**
     * Adds externally created widget to pannel
     */
    void RightPanelComponent::addToPanel(const tgui::Widget::Ptr &widgetPtr, const tgui::String &widgetName)
    {
        this->panel->add(widgetPtr, widgetName);
    }
}