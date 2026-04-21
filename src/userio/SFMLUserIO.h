#ifndef SFMLUSERIO_H_INCLUDED
#define SFMLUSERIO_H_INCLUDED

#include <TGUI/TGUI.hpp>
#include <TGUI/Backend/SFML-Graphics.hpp>
#include <SFML/Graphics.hpp>
#include <SFML/System.hpp>

#include "../ai/indiv.h"
#include "../params.h"
#include "../peeps.h"
#include "../utils/Save.h"
#include "../survivalCriteria/SurvivalCriteriaManager.h"

#include "./sfmlComponents/ViewComponent.h"
#include "./sfmlComponents/RightPanelComponent.h"
#include "./sfmlComponents/flowComponents/FlowControlComponent.h"
#include "./sfmlComponents/ConsoleComponent.h"
#include "./sfmlComponents/BottomButtonsComponent.h"
#include "./sfmlComponents/InfoWindowComponent.h"

namespace BS
{
    extern Peeps peeps;
    extern Grid grid;
    extern const Params &p;
    extern ParamManager paramManager;
    extern SurvivalCriteriaManager survivalCriteriaManager;
    extern std::stringstream printGenomeLegend();

    class SFMLUserIO
    {
    public:
        SFMLUserIO();
        ~SFMLUserIO();

        bool isStopped();
        bool isPaused();
        void pauseResume(bool paused);

        void updatePollEvents();
        void startNewGeneration(unsigned generation, unsigned stepsPerGeneration);
        void endOfStep(unsigned simStep);
        void endOfGeneration(unsigned generation);

        void settingsChanged(std::string name, std::string val);

        void log(std::string message);

        bool loadFileSelected = false;
        std::string loadFilename;

        void setFromParams();

        bool restartOnEnd = false;
    private:
        // Section heights at uiScale=1.0 (scaled by p.uiScale at runtime)
        static int const BASE_PANEL_WIDTH  = 280;
        static int const FLOW_H_BASE       = 120;
        static int const ACTION_H_BASE     = 95;
        static int const CONSOLE_H_BASE    = 60;

        int panelWidth;
        int windowWidth;
        int windowHeight;
        sf::RenderWindow* window;

        sf::View* view;
        ViewComponent* viewComponent;

        tgui::Gui gui;
        tgui::Panel::Ptr mainRightPanel;

        RightPanelComponent*    rightPanelComponent;
        FlowControlComponent*   flowControlComponent;
        BottomButtonsComponent* bottomButtonsComponent;
        InfoWindowComponent*    infoWindowComponent;

        bool paused = false;
        ConsoleComponent* console;

        static int const SPEED_SLOW_MAX = -5;
        static int const SPEED_FAST_MAX = 5;
        int speedThreshold = 0;
        int increaseSpeedCounter = 0;
        int slowSpeedCounter = 0;
        void speedChanged(float value);

        bool isChildWindowShowing = false;
        tgui::FileDialog::Ptr loadFileDialog;
        tgui::FileDialog::Ptr saveFileDialog;
        void childWindowToggled(bool shown);
        void initSaveFileDialog();
        void initLoadFileDialog();

        bool stopAtEnd = false;
        bool stopAtStart = false;

        std::vector<sf::RectangleShape> barriesrs;

        int getLiveDisplayScale();
        void applyUiScale(float scale);
        uint16_t selectedIndex = 0;

        bool passedSelected = false;
    };
}

#endif // SFMLUSERIO_H_INCLUDED
