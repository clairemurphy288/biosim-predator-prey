#include "BottomButtonsComponent.h"
#include "../../simulator.h"

namespace BS
{
    /**
     * Constructor
     * @param saveCallback save simulation callback
     * @param loadCallback load simulation callback
     * @param restartCallback restart simulation callback
     * @param saveIndivCallback save individual's neural network to file callback
     * @param changeSettingsCallback callback for changing settings
     * @param indivInfoCallback callback for showing informational child window
     * @param selectPassedCallback callback for selecting individuals tha passed the survival criteria
     */
    BottomButtonsComponent::BottomButtonsComponent(std::function<void(void)> saveCallback,
        std::function<void(void)> loadCallback,
        std::function<void(bool)> restartCallback,
        std::function<void()> saveIndivCallback,
        std::function<void(std::string name, std::string val)> changeSettingsCallback,
        std::function<void()> indivInfoCallback,
        std::function<void(bool)> selectPassedCallback)
    {
        this->selectPassedCallback = selectPassedCallback;

        this->group = tgui::Group::create();

        // setup divider
        tgui::SeparatorLine::Ptr line = tgui::SeparatorLine::create();
        line->setPosition("0%", "75%");
        line->setSize("100%", 1);
        line->getRenderer()->setColor(tgui::Color::Black);
        this->group->add(line);

        // setup buttons
        float btnHorizontalMargin = 5.f * p.uiScale;
        float height = 27.f * p.uiScale;
        float btnWidth = 72.f * p.uiScale;
        float btnWidthSmall = 57.f * p.uiScale;

        tgui::Button::Ptr saveButton = tgui::Button::create("Save sim");
        saveButton->setPosition({bindLeft(line) + 10.f * p.uiScale, bindTop(line) - height - 10.f * p.uiScale});
        saveButton->onPress([saveCallback]() { saveCallback(); });
        saveButton->setSize(btnWidth, height);
        this->group->add(saveButton, "SaveButton");

        tgui::Button::Ptr loadButton = tgui::Button::create("Load sim");
        loadButton->setPosition({bindRight(saveButton) + btnHorizontalMargin, bindTop(saveButton)});
        loadButton->onPress([loadCallback]() { loadCallback(); });
        loadButton->setSize(btnWidth, height);
        this->group->add(loadButton, "LoadButton");

        this->restartButton = tgui::ToggleButton::create("Restart");
        this->restartButton->setPosition({bindRight(loadButton) + btnHorizontalMargin, bindTop(loadButton)});
        this->restartButton->onToggle([restartCallback](bool isDown) {
            restartCallback(isDown);
        });
        this->restartButton->setSize(btnWidthSmall, height);
        this->group->add(this->restartButton, "RestartButton");

        tgui::CheckBox::Ptr autosaveCheckBox = tgui::CheckBox::create("Autosave");
        float checkboxSize = 16.f * p.uiScale;
        autosaveCheckBox->setSize(checkboxSize, checkboxSize);
        autosaveCheckBox->setPosition({bindLeft(saveButton), bindTop(loadButton) - checkboxSize * 2.0f});
        autosaveCheckBox->setText("Autosave");
        autosaveCheckBox->setChecked(p.autoSave);
        autosaveCheckBox->onChange([changeSettingsCallback](bool checked){
            changeSettingsCallback("autosave", checked ? "1" : "0");
        });
        this->group->add(autosaveCheckBox, "AutosaveCheckBox");

        tgui::Button::Ptr saveIndivBtn = tgui::Button::create("Save indiv");
        saveIndivBtn->setSize(btnWidth, height);
        saveIndivBtn->setPosition({bindRight(this->restartButton) - saveIndivBtn->getSize().x, bindTop(this->restartButton) - saveIndivBtn->getSize().y - 10.f * p.uiScale});
        saveIndivBtn->onPress([saveIndivCallback]() { saveIndivCallback(); });
        this->group->add(saveIndivBtn, "SaveIndivBtn");

        tgui::Button::Ptr indivInfoBtn = tgui::Button::create("i");
        indivInfoBtn->setSize(height, height);
        indivInfoBtn->setPosition({bindLeft(saveIndivBtn) - indivInfoBtn->getSize().x - btnHorizontalMargin, bindTop(saveIndivBtn)});
        indivInfoBtn->onPress([indivInfoCallback]() { indivInfoCallback(); });
        this->group->add(indivInfoBtn, "IndivInfoBtn");

        this->selectPassedBtn = tgui::Button::create("Passed");
        this->selectPassedBtn->setSize(btnWidthSmall, height);
        this->selectPassedBtn->setPosition({bindLeft(saveIndivBtn), bindTop(saveIndivBtn) - this->selectPassedBtn->getSize().y - 10.f * p.uiScale});
        this->selectPassedBtn->onPress([this]() {
            this->isSelectPassed = !this->isSelectPassed;
            this->selectPassedBtn->setText(this->isSelectPassed ? "Clear" : "Passed");
            this->selectPassedCallback(this->isSelectPassed);
        });
        this->group->add(selectPassedBtn, "SelectPassedBtn");
    }    
    
    void BottomButtonsComponent::switchPassedSelection(bool selected)
    {
        this->isSelectPassed = selected;
        this->selectPassedBtn->setText(this->isSelectPassed ? "Clear" : "Passed");
        this->selectPassedCallback(this->isSelectPassed); 
    }

    void BottomButtonsComponent::flushRestartButton()
    {
        this->restartButton->setDown(false);
    }

    tgui::Group::Ptr BottomButtonsComponent::getGroup() 
    { 
        return this->group; 
    } 
}