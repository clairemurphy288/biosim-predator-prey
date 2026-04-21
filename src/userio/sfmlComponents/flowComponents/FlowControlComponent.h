#ifndef FLOWCONTROLCOMPONENT_H_INCLUDED
#define FLOWCONTROLCOMPONENT_H_INCLUDED

#include <functional>
#include <TGUI/TGUI.hpp>
#include <TGUI/Backend/SFML-Graphics.hpp>

namespace BS
{
    /**
     * Adds simulation flow controls (play/pause, speed, progress, pause-at options)
     * directly into the given container panel.
     */
    class FlowControlComponent
    {
    public:
        FlowControlComponent(
            tgui::Container::Ptr container,
            int speedMin,
            int speedMax,
            int speedInitValue,
            std::function<void(float value)> changeSpeedCallback,
            std::function<void(bool)> pauseCallback,
            std::function<void(bool, bool)> stopAtSmthCallback
        );
        ~FlowControlComponent();

        void startNewGeneration(unsigned generation, unsigned stepsPerGeneration);
        void endOfStep(unsigned simStep);

        void pauseResume();
        void pauseResume(bool paused);
        void pauseExternal(bool paused);
        void flushStopAtSmthButtons();

    private:
        tgui::Container::Ptr container;

        tgui::Picture::Ptr pausePicture;
        std::function<void(bool)> pauseCallback;
        bool paused = false;
        bool externalPause = false;

        tgui::ProgressBar::Ptr generationProgressBar;

        std::function<void(bool, bool)> stopAtSmthCallback;
        tgui::CheckBox::Ptr stopAtStartButton;
        tgui::CheckBox::Ptr stopAtEndButton;
    };
}

#endif
