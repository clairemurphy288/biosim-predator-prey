#include "UserIO.h"
#include "../ai/indiv.h"
#include <algorithm>

namespace BS {

    UserIO::UserIO(bool windowInit, bool videoSaveInit)
    {
        if (windowInit) 
            this->sfmlView = new SFMLUserIO();
        if (videoSaveInit) 
            this->imageWriter = new ImageWriter();     
        
    }

    UserIO::~UserIO()
    {
        if (this->sfmlView != nullptr)
            delete this->sfmlView;
        if (this->imageWriter != nullptr)
            delete this->imageWriter;
    }

    /**
     * Check if the simulation should be stopped (e.g. because of closed window)
     */
    bool UserIO::isStopped()
    {
        if (this->sfmlView != nullptr)
            return this->sfmlView->isStopped();
        return false;
    }

    /**
     * Should be called at the end of each generation
     */
    void UserIO::startNewGeneration(unsigned generation, unsigned stepsPerGeneration)
    {
        if (this->sfmlView != nullptr) {
            this->sfmlView->startNewGeneration(generation, stepsPerGeneration);
        }
        if (p.autoSave) 
        {
            std::stringstream filename;
            filename << "Output/Saves/peeps-"
                        << std::setfill('0') << std::setw(6) << generation
                        << ".bin";            
            Save::save(filename.str());
        }
    }

    /**
     * Should be called at the end of each step
     */
    void UserIO::handleStep(unsigned simStep, unsigned generation)
    {
        if (this->sfmlView != nullptr)
        {
            // handle pause/unpause
            while (this->isPaused() && !this->isStopped() ) {
                this->sfmlView->endOfStep(simStep);
            }
            this->sfmlView->endOfStep(simStep);
        }

        if (this->imageWriter != nullptr)
            this->imageWriter->endOfStep(simStep, generation);
    }

    /**
     * Should be called at the end of each generation
     */
    void UserIO::endOfGeneration(unsigned generation)
    {
        if (this->sfmlView != nullptr)
            this->sfmlView->endOfGeneration(generation);

        if (this->imageWriter != nullptr)
            this->imageWriter->endOfGeneration(generation);

        // Neural net auto-save — runs in both headless and windowed mode.
        if (p.autoSaveNetEpochs > 0
                && generation < p.autoSaveNetEpochs
                && generation % p.autoSaveNetStride == 0
                && (p.autoSavePredatorNetsPerGeneration > 0 || p.autoSavePreyNetsPerGeneration > 0)) {

            std::vector<uint16_t> predIdxs, preyIdxs;
            predIdxs.reserve(p.population);
            preyIdxs.reserve(p.population);
            for (uint16_t idx = 1; idx <= p.population; ++idx) {
                const Indiv &indiv = peeps[idx];
                if (!indiv.alive || indiv.nnet.connections.empty()) continue;
                if (indiv.type == AgentType::PREDATOR) predIdxs.push_back(idx);
                else                                   preyIdxs.push_back(idx);
            }

            const std::string base = p.imageDir + "/gen-" + std::to_string(generation);
            const unsigned nPred = std::min(p.autoSavePredatorNetsPerGeneration,
                                            (unsigned)predIdxs.size());
            const unsigned nPrey = std::min(p.autoSavePreyNetsPerGeneration,
                                            (unsigned)preyIdxs.size());
            for (unsigned i = 0; i < nPred; ++i)
                Save::saveNetAsFile(predIdxs[i], base + "-pred-id-" + std::to_string(predIdxs[i]) + ".svg");
            for (unsigned i = 0; i < nPrey; ++i)
                Save::saveNetAsFile(preyIdxs[i], base + "-prey-id-" + std::to_string(preyIdxs[i]) + ".svg");
        }

        if (p.updateGraphLog && (generation == 1 || ((generation % p.updateGraphLogStride) == 0))) {
            std::system(p.graphLogUpdateCommand.c_str());
        }
    }

    void UserIO::log(std::string message)
    {
        if (this->sfmlView != nullptr)
            this->sfmlView->log(message);
        
        std::cout << message << std::endl;
    }

    /**
     * Check if the simulation is paused
     */
    bool UserIO::isPaused()
    {
        if (this->sfmlView != nullptr)
            return this->sfmlView->isPaused() && !this->sfmlView->loadFileSelected;

        return false;
    }

    /**
     * Check if a simulation should be switched into "load simulation" mode
     */
    bool UserIO::getLoadFileSelected()
    {
        if (this->sfmlView != nullptr)
        {
            return this->sfmlView->loadFileSelected;
        }
        return false;
    }

    /**
     * Get the filename of the simulation to load
     */
    std::string UserIO::getLoadFilename()
    {
        if (this->sfmlView != nullptr)
        {
            return this->sfmlView->loadFilename;
        }
        return "";
    }

    /**
     * Clean loading selection after loading a simulation
     */
    void UserIO::cleanLoadSelection()
    {
        if (this->sfmlView != nullptr)
        {
            this->sfmlView->loadFilename = "";
            this->sfmlView->loadFileSelected = false;
        }
    }

    /**
     * Update the view from the parameters
     */
    void UserIO::setFromParams()
    {
        if (this->sfmlView != nullptr)
        {        
            this->sfmlView->setFromParams();
        }
    }

    /**
     * Check if the simulation should restart at the end of this generation
     */
    bool UserIO::getRestartAtEnd()
    {
        if (this->sfmlView != nullptr)
        {        
            return this->sfmlView->restartOnEnd;
        }
        return false;
    }
}