#include "imageWriter.h"

namespace BS {

ImageWriter::ImageWriter()
{
    droppedFrameCount = 0;
}

void ImageWriter::startNewGeneration() {}

bool ImageWriter::saveVideoFrameSync(unsigned /*simStep*/, unsigned /*generation*/)
{
    return false;
}

void ImageWriter::saveGenerationVideo(unsigned /*generation*/) {}

void ImageWriter::abort() {}

void ImageWriter::endOfStep(unsigned /*simStep*/, unsigned /*generation*/) {}

void ImageWriter::endOfGeneration(unsigned /*generation*/) {}

} // namespace BS

