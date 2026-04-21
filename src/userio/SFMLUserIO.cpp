#include "SFMLUserIO.h"

namespace BS
{
    SFMLUserIO::SFMLUserIO()
    {
        // Derive window size from simulation grid
        this->panelWidth   = static_cast<int>(BASE_PANEL_WIDTH * p.uiScale);
        int liveScale      = static_cast<int>(p.displayScale / p.uiScale);
        int simW           = p.sizeX * liveScale;
        int simH           = p.sizeY * liveScale;
        this->windowWidth  = simW + this->panelWidth;
        this->windowHeight = std::max(simH, 500);

        this->window = new sf::RenderWindow(
            sf::VideoMode(sf::Vector2u(static_cast<unsigned>(this->windowWidth), static_cast<unsigned>(this->windowHeight))),
            "biosim4",
            sf::Style::Close | sf::Style::Titlebar);
        this->window->setFramerateLimit(144);
        this->window->setVerticalSyncEnabled(false);
        this->window->setPosition(sf::Vector2i(
            200,
            (static_cast<int>(sf::VideoMode::getDesktopMode().size.y) - this->windowHeight) / 2));

        this->gui.setWindow(*this->window);
        tgui::Theme::setDefault("./Resources/Flat.txt");
        this->gui.setTextSize(static_cast<unsigned>(13 * p.uiScale));

        // ── Build the right panel with 4 explicit sections ────────────────
        int flowH   = static_cast<int>(FLOW_H_BASE   * p.uiScale);
        int actionH = static_cast<int>(ACTION_H_BASE * p.uiScale);
        int conH    = static_cast<int>(CONSOLE_H_BASE* p.uiScale);
        int settH   = this->windowHeight - flowH - actionH - conH;

        this->mainRightPanel = tgui::Panel::create();
        this->mainRightPanel->setSize(this->panelWidth, this->windowHeight);
        this->mainRightPanel->setAutoLayout(tgui::AutoLayout::Right);

        // Flow controls (top)
        auto flowPanel = tgui::Panel::create();
        flowPanel->setPosition(0, 0);
        flowPanel->setSize(this->panelWidth, flowH);
        this->mainRightPanel->add(flowPanel, "FlowPanel");

        // Settings (scrollable middle)
        auto settPanel = tgui::ScrollablePanel::create();
        settPanel->setPosition(0, flowH);
        settPanel->setSize(this->panelWidth, settH);
        this->mainRightPanel->add(settPanel, "SettPanel");

        // Actions (below settings)
        auto actionPanel = tgui::Panel::create();
        actionPanel->setPosition(0, flowH + settH);
        actionPanel->setSize(this->panelWidth, actionH);
        this->mainRightPanel->add(actionPanel, "ActionPanel");

        // Console (bottom)
        auto conPanel = tgui::Panel::create();
        conPanel->setPosition(0, flowH + settH + actionH);
        conPanel->setSize(this->panelWidth, conH);
        this->mainRightPanel->add(conPanel, "ConPanel");

        // ── Info window ───────────────────────────────────────────────────
        this->infoWindowComponent = new InfoWindowComponent([this] {
            this->childWindowToggled(false);
        });

        // ── Flow controls ─────────────────────────────────────────────────
        this->flowControlComponent = new FlowControlComponent(
            flowPanel,
            SPEED_SLOW_MAX, SPEED_FAST_MAX, 0,
            [this](float value) { this->speedChanged(value); },
            [this](bool paused) { this->pauseResume(paused); },
            [this](bool atStart, bool atEnd) {
                this->stopAtStart = atStart;
                this->stopAtEnd   = atEnd;
            }
        );

        // ── Settings ─────────────────────────────────────────────────────
        this->rightPanelComponent = new RightPanelComponent(
            settPanel,
            this->panelWidth,
            [this](std::string name, std::string val) { this->settingsChanged(name, val); },
            [this]() {
                if (this->isChildWindowShowing) return;
                for (unsigned i = 0; i < survivalCriteriaManager.survivalCriteriasVector.size(); ++i)
                    this->infoWindowComponent->append(
                        survivalCriteriaManager.survivalCriteriasVector[i]->text + ": \n" +
                        survivalCriteriaManager.survivalCriteriasVector[i]->description + "\n");
                this->childWindowToggled(true);
                this->gui.add(this->infoWindowComponent->getChildWindow());
            },
            [this](float scale) { this->applyUiScale(scale); }
        );

        // ── Action buttons ────────────────────────────────────────────────
        this->bottomButtonsComponent = new BottomButtonsComponent(
            actionPanel,
            [this]() {
                if (this->isChildWindowShowing) return;
                this->initSaveFileDialog();
                this->saveFileDialog->setPath("Output/Saves");
                this->childWindowToggled(true);
                this->gui.add(this->saveFileDialog);
            },
            [this]() {
                if (this->isChildWindowShowing) return;
                this->initLoadFileDialog();
                this->loadFileDialog->setPath("Output/Saves");
                this->childWindowToggled(true);
                this->gui.add(this->loadFileDialog);
            },
            [this](bool restart) { this->restartOnEnd = restart; },
            [this]() {
                this->flowControlComponent->pauseResume(true);
                if (this->selectedIndex != 0) {
                    std::string filename = Save::saveNet(this->selectedIndex);
                    this->log("Saved into: " + filename);
                }
            },
            [this](std::string name, std::string val) { this->settingsChanged(name, val); },
            [this]() {
                if (this->isChildWindowShowing) return;
                std::stringstream legendStream = printGenomeLegend();
                this->infoWindowComponent->append(legendStream.str());
                if (this->selectedIndex != 0) {
                    std::stringstream indivStream = peeps[this->selectedIndex].printNeuralNet();
                    this->infoWindowComponent->append(indivStream.str());
                    this->infoWindowComponent->append("\nLocation: " +
                        std::to_string(peeps[this->selectedIndex].loc.x) + ", " +
                        std::to_string(peeps[this->selectedIndex].loc.y));
                }
                this->childWindowToggled(true);
                this->gui.add(this->infoWindowComponent->getChildWindow());
            },
            [this](bool select) {
                if (select) {
                    this->passedSelected = true;
                    peeps[this->selectedIndex].shape.setOutlineThickness(0.f);
                    this->selectedIndex = 0;
                    for (uint16_t index = 1; index <= p.population; ++index) {
                        if (survivalCriteriaManager.passedSurvivalCriterion(peeps[index], p, grid).first) {
                            peeps[index].shape.setOutlineColor(sf::Color::White);
                            peeps[index].shape.setOutlineThickness(1.f);
                        }
                    }
                } else {
                    this->passedSelected = false;
                    for (uint16_t index = 1; index <= p.population; ++index)
                        peeps[index].shape.setOutlineThickness(0.f);
                }
            }
        );

        // ── Console ───────────────────────────────────────────────────────
        this->console = new ConsoleComponent();
        conPanel->add(this->console->getConsole());

        this->gui.add(this->mainRightPanel);

        // ── Simulation view ───────────────────────────────────────────────
        this->viewComponent = new ViewComponent(this->window->getSize());
        this->view = this->viewComponent->getView();
    }

    void SFMLUserIO::initSaveFileDialog()
    {
        if (this->saveFileDialog == nullptr)
        {
            this->saveFileDialog = tgui::FileDialog::create("Save file", "Save");
            this->saveFileDialog->setMultiSelect(false);
            this->saveFileDialog->setFileMustExist(false);
            this->saveFileDialog->setPath("Output/Saves");
            this->saveFileDialog->setFilename("simulation.bin");
            this->saveFileDialog->setPosition("5%", "5%");
            this->saveFileDialog->onFileSelect([this](const tgui::String &filePath) {
                Save::save(filePath.toStdString());
                this->childWindowToggled(false);
            });
            this->saveFileDialog->onCancel([this] { this->childWindowToggled(false); });
        }
    }

    void SFMLUserIO::initLoadFileDialog()
    {
        if (this->loadFileDialog == nullptr)
        {
            this->loadFileDialog = tgui::FileDialog::create("Open file", "Open");
            this->loadFileDialog->setMultiSelect(false);
            this->loadFileDialog->setFileMustExist(true);
            this->loadFileDialog->setPath("Output/Saves");
            this->loadFileDialog->setFilename("simulation.bin");
            this->loadFileDialog->setPosition("5%", "5%");
            this->loadFileDialog->onFileSelect([this](const tgui::String &filePath) {
                this->loadFileSelected = true;
                this->loadFilename = filePath.toStdString();
                this->childWindowToggled(false);
            });
            this->loadFileDialog->onCancel([this] {
                std::cerr << "No file selected.\n";
                this->childWindowToggled(false);
            });
        }
    }

    void SFMLUserIO::setFromParams()
    {
        this->rightPanelComponent->setFromParams();
    }

    void SFMLUserIO::childWindowToggled(bool shown)
    {
        if (shown)
            this->viewComponent->lock();
        else
            this->viewComponent->unlock();
        this->flowControlComponent->pauseExternal(shown);
        this->isChildWindowShowing = shown;
    }

    SFMLUserIO::~SFMLUserIO()
    {
        delete this->window;
    }

    bool SFMLUserIO::isStopped()
    {
        return !this->window->isOpen();
    }

    void SFMLUserIO::updatePollEvents()
    {
        while (const std::optional<sf::Event> optEvent = this->window->pollEvent())
        {
            const sf::Event &e = *optEvent;

            if (e.is<sf::Event::Closed>())
                this->window->close();

            if (const auto *keyPressed = e.getIf<sf::Event::KeyPressed>();
                keyPressed && keyPressed->code == sf::Keyboard::Key::Escape)
                this->window->close();

            if (const auto *keyPressed = e.getIf<sf::Event::KeyPressed>();
                keyPressed && keyPressed->code == sf::Keyboard::Key::Space)
                this->flowControlComponent->pauseResume(!this->paused);

            this->viewComponent->updateInput(e, this->window);

            if (const auto *mouseReleased = e.getIf<sf::Event::MouseButtonReleased>())
            {
                if (mouseReleased->button == sf::Mouse::Button::Right && !this->passedSelected)
                {
                    int liveDisplayScale = this->getLiveDisplayScale();
                    sf::Vector2f mousePosition = this->window->mapPixelToCoords(sf::Mouse::getPosition(*window));
                    std::cout << mousePosition.x << " " << mousePosition.y << std::endl;

                    int16_t x = floor(mousePosition.x / liveDisplayScale);
                    int16_t y = ceil(p.sizeY - 1 - mousePosition.y / liveDisplayScale);

                    if (x >= 0 && x < p.sizeX && y >= 0 && y < p.sizeY)
                    {
                        uint16_t index = grid.at(x, y);
                        if (this->selectedIndex != 0 && this->selectedIndex != index) {
                            peeps[this->selectedIndex].shape.setOutlineThickness(0.f);
                            this->selectedIndex = 0;
                        }
                        if (index != 0) {
                            peeps[index].shape.setOutlineColor(sf::Color::White);
                            peeps[index].shape.setOutlineThickness(1.f);
                            this->selectedIndex = index;
                        }
                    } else if (this->selectedIndex != 0) {
                        peeps[this->selectedIndex].shape.setOutlineThickness(0.f);
                        this->selectedIndex = 0;
                    }
                }
            }

            this->gui.handleEvent(e);
        }
    }

    void SFMLUserIO::startNewGeneration(unsigned generation, unsigned stepsPerGeneration)
    {
        this->flowControlComponent->startNewGeneration(generation, stepsPerGeneration);
        this->updatePollEvents();
        if (this->stopAtStart)
        {
            this->flowControlComponent->pauseResume(true);
            this->flowControlComponent->flushStopAtSmthButtons();
        }

        this->bottomButtonsComponent->flushRestartButton();

        int liveDisplayScale = this->getLiveDisplayScale();
        barriesrs.clear();
        auto const &barrierLocs = grid.getBarrierLocations();
        for (Coord loc : barrierLocs) {
            sf::RectangleShape barrier(sf::Vector2f(1.f * liveDisplayScale, 1.f * liveDisplayScale));
            barrier.setPosition(sf::Vector2f(
                static_cast<float>(loc.x * liveDisplayScale),
                static_cast<float>((p.sizeY - (loc.y + 1.f)) * liveDisplayScale)));
            barrier.setFillColor(sf::Color(136, 136, 136));
            barriesrs.push_back(barrier);
        }

        survivalCriteriaManager.initShapes(liveDisplayScale);

        if (this->selectedIndex != 0) {
            peeps[this->selectedIndex].shape.setOutlineThickness(0.f);
            this->selectedIndex = 0;
        }

        this->bottomButtonsComponent->switchPassedSelection(false);
    }

    void SFMLUserIO::endOfStep(unsigned simStep)
    {
        if (this->stopAtEnd && simStep == p.stepsPerGeneration - 2) {
            this->flowControlComponent->pauseResume(true);
            this->flowControlComponent->flushStopAtSmthButtons();
        }
        if (this->increaseSpeedCounter < this->speedThreshold)
        {
            this->increaseSpeedCounter++;
            return;
        }
        this->increaseSpeedCounter = 0;

        do
        {
            this->updatePollEvents();

            this->flowControlComponent->endOfStep(simStep);
            this->window->setView(*this->view);
            this->window->clear();

            int liveDisplayScale = this->getLiveDisplayScale();
            for (uint16_t index = 1; index <= p.population; ++index)
            {
                Indiv &indiv = peeps[index];
                if (indiv.alive)
                {
                    indiv.shape.setPosition(sf::Vector2f(
                        static_cast<float>(indiv.loc.x * liveDisplayScale),
                        static_cast<float>(((p.sizeY - indiv.loc.y) - 1) * liveDisplayScale)));
                    this->window->draw(indiv.shape);
                }
            }

            for (sf::RectangleShape &barrier : barriesrs)
                this->window->draw(barrier);

            for (sf::Drawable *shape : survivalCriteriaManager.getShapes())
                this->window->draw(*shape);

            this->gui.draw();
            this->window->display();

            this->slowSpeedCounter--;
        } while (this->slowSpeedCounter >= this->speedThreshold);
        this->slowSpeedCounter = 0;
    }

    int SFMLUserIO::getLiveDisplayScale()
    {
        return p.displayScale / p.uiScale;
    }

    void SFMLUserIO::endOfGeneration(unsigned generation) {}

    void SFMLUserIO::log(std::string message)
    {
        this->console->log(message);
    }

    void SFMLUserIO::pauseResume(bool paused)
    {
        this->paused = paused;
    }

    bool SFMLUserIO::isPaused()
    {
        return this->paused;
    }

    void SFMLUserIO::settingsChanged(std::string name, std::string val)
    {
        paramManager.changeFromUi(name, val);
    }

    void SFMLUserIO::applyUiScale(float scale)
    {
        this->settingsChanged("uiscale", std::to_string(scale));

        this->panelWidth   = static_cast<int>(BASE_PANEL_WIDTH * scale);
        int liveScale      = static_cast<int>(p.displayScale / scale);
        this->windowWidth  = p.sizeX * liveScale + this->panelWidth;
        this->windowHeight = std::max(p.sizeY * liveScale, 500);

        this->window->setSize(sf::Vector2u(this->windowWidth, this->windowHeight));
        this->window->setPosition(sf::Vector2i(
            200,
            (static_cast<int>(sf::VideoMode::getDesktopMode().size.y) - this->windowHeight) / 2));

        this->mainRightPanel->setSize(this->panelWidth, this->windowHeight);

        int flowH   = static_cast<int>(FLOW_H_BASE   * scale);
        int actionH = static_cast<int>(ACTION_H_BASE * scale);
        int conH    = static_cast<int>(CONSOLE_H_BASE* scale);
        int settH   = this->windowHeight - flowH - actionH - conH;

        auto settPanel   = this->mainRightPanel->get<tgui::ScrollablePanel>("SettPanel");
        auto actionPanel = this->mainRightPanel->get<tgui::Panel>("ActionPanel");
        auto conPanel    = this->mainRightPanel->get<tgui::Panel>("ConPanel");

        settPanel->setPosition(0, flowH);
        settPanel->setSize(this->panelWidth, settH);
        actionPanel->setPosition(0, flowH + settH);
        actionPanel->setSize(this->panelWidth, actionH);
        conPanel->setPosition(0, flowH + settH + actionH);
        conPanel->setSize(this->panelWidth, conH);

        this->viewComponent->resize(sf::Vector2u(this->windowWidth, this->windowHeight));
        this->view = this->viewComponent->getView();
    }

    void SFMLUserIO::speedChanged(float value)
    {
        this->speedThreshold = value;
    }
}
