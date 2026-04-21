#include "BottomButtonsComponent.h"
#include "../../simulator.h"

namespace BS
{
    BottomButtonsComponent::BottomButtonsComponent(
        tgui::Container::Ptr container_,
        std::function<void(void)> saveCallback,
        std::function<void(void)> loadCallback,
        std::function<void(bool)> restartCallback,
        std::function<void()> saveIndivCallback,
        std::function<void(std::string name, std::string val)> changeSettingsCallback,
        std::function<void()> indivInfoCallback,
        std::function<void(bool)> selectPassedCallback_)
    {
        this->container = container_;
        this->selectPassedCallback = selectPassedCallback_;

        float s  = p.uiScale;
        float mx = 10.f * s;          // horizontal margin
        float my = 8.f  * s;          // top margin
        float bh = 24.f * s;          // button height
        float ch = 14.f * s;          // checkbox height
        float vg = 7.f  * s;          // vertical gap between rows

        // ── Row 1: Autosave checkbox ──────────────────────────────────────
        tgui::CheckBox::Ptr autosaveBox = tgui::CheckBox::create("Autosave");
        autosaveBox->setSize(ch, ch);
        autosaveBox->setPosition({mx, my});
        autosaveBox->setChecked(p.autoSave);
        autosaveBox->onChange([changeSettingsCallback](bool checked) {
            changeSettingsCallback("autosave", checked ? "1" : "0");
        });
        this->container->add(autosaveBox, "AutosaveBox");

        // ── Row 2: Save / Load / Restart ──────────────────────────────────
        float row2Y = my + ch + vg;
        // Button widths use TGUI percentage strings applied per widget
        tgui::Button::Ptr saveBtn = tgui::Button::create("Save sim");
        saveBtn->setPosition({mx, row2Y});
        saveBtn->setSize("28%", bh);
        saveBtn->onPress([saveCallback]() { saveCallback(); });
        this->container->add(saveBtn, "SaveBtn");

        tgui::Button::Ptr loadBtn = tgui::Button::create("Load sim");
        loadBtn->setPosition({bindRight(saveBtn) + 4.f * s, row2Y});
        loadBtn->setSize("28%", bh);
        loadBtn->onPress([loadCallback]() { loadCallback(); });
        this->container->add(loadBtn, "LoadBtn");

        this->restartButton = tgui::ToggleButton::create("Restart");
        this->restartButton->setPosition({bindRight(loadBtn) + 4.f * s, row2Y});
        this->restartButton->setSize("22%", bh);
        this->restartButton->onToggle([restartCallback](bool isDown) {
            restartCallback(isDown);
        });
        this->container->add(this->restartButton, "RestartBtn");

        // ── Row 3: Save indiv / Info / Show passed ────────────────────────
        float row3Y = row2Y + bh + vg;

        tgui::Button::Ptr saveIndivBtn = tgui::Button::create("Save indiv");
        saveIndivBtn->setPosition({mx, row3Y});
        saveIndivBtn->setSize("28%", bh);
        saveIndivBtn->onPress([saveIndivCallback]() { saveIndivCallback(); });
        this->container->add(saveIndivBtn, "SaveIndivBtn");

        tgui::Button::Ptr indivInfoBtn = tgui::Button::create("i");
        indivInfoBtn->setPosition({bindRight(saveIndivBtn) + 4.f * s, row3Y});
        indivInfoBtn->setSize(bh, bh);
        indivInfoBtn->onPress([indivInfoCallback]() { indivInfoCallback(); });
        this->container->add(indivInfoBtn, "IndivInfoBtn");

        this->selectPassedBtn = tgui::Button::create("Passed");
        this->selectPassedBtn->setPosition({bindRight(indivInfoBtn) + 4.f * s, row3Y});
        this->selectPassedBtn->setSize("22%", bh);
        this->selectPassedBtn->onPress([this]() {
            this->isSelectPassed = !this->isSelectPassed;
            this->selectPassedBtn->setText(this->isSelectPassed ? "Clear" : "Passed");
            this->selectPassedCallback(this->isSelectPassed);
        });
        this->container->add(this->selectPassedBtn, "SelectPassedBtn");
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
}
