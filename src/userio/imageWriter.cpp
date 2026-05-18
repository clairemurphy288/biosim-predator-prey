// imageWriter.cpp

#include <iostream>
#include <sstream>
#include <iomanip>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include "../simulator.h"
#include "imageWriter.h"
#define cimg_use_opencv 1
#define cimg_display 0
#include "CImg.h"

namespace BS {

cimg_library::CImgList<uint8_t> imageList;

// Pushes a new image frame onto .imageList.
//
void saveOneFrameImmed(const ImageFrameData &data)
{
    using namespace cimg_library;

    CImg<uint8_t> image(p.sizeX * p.displayScale, p.sizeY * p.displayScale,
                        1,   // Z depth
                        3,   // color channels
                        0);  // black background
    uint8_t color[3];
    std::stringstream imageFilename;
    imageFilename << p.imageDir << "frame-"
                  << std::setfill('0') << std::setw(6) << data.generation
                  << '-' << std::setfill('0') << std::setw(6) << data.simStep
                  << ".png";

    // Draw barrier locations

    color[0] = color[1] = color[2] = 0x88;
    for (Coord loc : data.barrierLocs) {
            image.draw_rectangle(
                loc.x       * p.displayScale - (p.displayScale / 2) + p.agentSize / 2, 
                ((p.sizeY - loc.y) - 1)   * p.displayScale - (p.displayScale / 2) + p.agentSize / 2,
                (loc.x + 1) * p.displayScale + p.agentSize / 2, 
                ((p.sizeY - (loc.y - 0))) * p.displayScale + p.agentSize / 2,
                color,  // rgb
                1.0);  // alpha
    }

    // Draw agents

    for (size_t i = 0; i < data.indivLocs.size(); ++i) {
        if (data.indivColors[i]) {
            color[0] = 220; color[1] = 60;  color[2] = 60;  // predator: red
        } else {
            color[0] = 60;  color[1] = 220; color[2] = 120; // prey: green
        }

        image.draw_circle(
                data.indivLocs[i].x * p.displayScale + p.agentSize,
                ((p.sizeY - data.indivLocs[i].y) - 1) * p.displayScale + p.agentSize,
                p.agentSize,
                color,  // rgb
                1.0);  // alpha
    }

    //image.save_png(imageFilename.str().c_str(), 3);
    imageList.push_back(image);

    //CImgDisplay local(image, "biosim3");
}


// Starts the image writer asynchronous thread.
ImageWriter::ImageWriter()
    : droppedFrameCount{0}, busy{true}, dataReady{false},
      abortRequested{false}
{
    startNewGeneration();
}


void ImageWriter::startNewGeneration()
{
    imageList.clear();
    skippedFrames = 0;
}


// Synchronous version, always returns true
bool ImageWriter::saveVideoFrameSync(unsigned simStep, unsigned generation)
{
    // We cache a local copy of data from params, grid, and peeps because
    // those objects will change by the main thread at the same time our
    // saveFrameThread() is using it to output a video frame.
    data.simStep = simStep;
    data.generation = generation;
    data.indivLocs.clear();
    data.indivColors.clear();
    data.barrierLocs.clear();
    data.signalLayers.clear();

    //todo!!!
    for (uint16_t index = 1; index <= p.population; ++index) {
        Indiv &indiv = peeps[index];
        if (indiv.alive) {
            data.indivLocs.push_back(indiv.loc);
            data.indivColors.push_back(indiv.type == AgentType::PREDATOR ? 1 : 0);
        }
    }

    auto const &barrierLocs = grid.getBarrierLocations();
    for (Coord loc : barrierLocs) {
        data.barrierLocs.push_back(loc);
    }

    saveOneFrameImmed(data);
    return true;
}


// ToDo: put save_video() in its own thread
void ImageWriter::saveGenerationVideo(unsigned generation)
{
    if (imageList.size() > 0) {
        std::stringstream videoFilename;
        videoFilename << p.imageDir.c_str() << "/gen-"
                      << std::setfill('0') << std::setw(6) << generation
                      << ".avi";
        cv::setNumThreads(2);
        imageList.save_video(videoFilename.str().c_str(),
                             p.videoFps,
                             "H264");
        if (skippedFrames > 0) {
            std::cout << "Video skipped " << skippedFrames << " frames" << std::endl;
        }
    }
    startNewGeneration();
}


void ImageWriter::abort()
{
    busy =true;
    abortRequested = true;
    {
        std::lock_guard<std::mutex> lck(mutex_);
        dataReady = true;
    }
    condVar.notify_one();
}


void ImageWriter::endOfStep(unsigned simStep, unsigned generation)
{
    if (p.saveVideo &&
            ((generation % p.videoStride) == 0
            || generation <= p.videoSaveFirstFrames
            || (generation >= p.parameterChangeGenerationNumber
            && generation <= p.parameterChangeGenerationNumber + p.videoSaveFirstFrames))) {
        if (!this->saveVideoFrameSync(simStep, generation)) {
            std::cout << "imageWriter busy" << std::endl;
        }
    }
}

void ImageWriter::endOfGeneration(unsigned generation)
{
    if (p.saveVideo &&
            ((generation % p.videoStride) == 0
            || generation <= p.videoSaveFirstFrames
            || (generation >= p.parameterChangeGenerationNumber
            && generation <= p.parameterChangeGenerationNumber + p.videoSaveFirstFrames))) {
        this->saveGenerationVideo(generation);
    }
}

} // end namespace BS
