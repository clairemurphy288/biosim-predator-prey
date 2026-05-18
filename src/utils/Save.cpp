#include "Save.h"
#include "../simulator.h"
#include <filesystem>

namespace BS
{
    namespace {
        std::string g_lastNetSaveError;
    }

    /**
     * Saves simulation in binary format using cereal library
     * see void serialize(Archive &ar) function in class Peeps and class Params
     */
    void Save::save(std::string fileName)
    {
        std::ofstream file(fileName);
        cereal::BinaryOutputArchive archive(file);
        Params newParams;
        archive(peeps, p);
    }

    /**
     * Loads simulation from binary file into peeps and Params
     */
    void Save::load(std::string fileName)
    {
        std::ifstream file(fileName);
        cereal::BinaryInputArchive archive(file);        
        Params newParams;
        archive(peeps, newParams);
        paramManager.updateFromSave(newParams);
    }

    /**
     * Saves neural network image using printIGraphEdgeList of indiv
     * and graph-nnet.py script
     */
    const std::string &Save::lastNetSaveError()
    {
        return g_lastNetSaveError;
    }

    std::string Save::saveNetAsFile(int selectedIndex, const std::string &filename)
    {
        g_lastNetSaveError.clear();

        if (selectedIndex <= 0 || selectedIndex > static_cast<int>(p.population)) {
            g_lastNetSaveError = "Selected individual index is out of range.";
            return "";
        }
        if (peeps[selectedIndex].nnet.connections.empty()) {
            g_lastNetSaveError = "Selected individual has an empty neural net.";
            return "";
        }

        const std::string edgeList = peeps[selectedIndex].printIGraphEdgeList().str();
        if (edgeList.empty()) {
            g_lastNetSaveError = "Selected individual produced an empty NN edge list.";
            return "";
        }

        std::filesystem::path outputPath(filename);
        std::filesystem::path inputPath = outputPath;
        inputPath.replace_extension(".txt");
        if (inputPath.has_parent_path()) {
            std::filesystem::create_directories(inputPath.parent_path());
        }
        if (outputPath.has_parent_path()) {
            std::filesystem::create_directories(outputPath.parent_path());
        }

        std::ofstream outFile(inputPath.string());
        if (!outFile.is_open()) {
            g_lastNetSaveError = "Could not open NN edge-list file for writing: " + inputPath.string();
            return "";
        }

        outFile << edgeList;
        if (!outFile.good()) {
            g_lastNetSaveError = "Failed while writing NN edge-list file: " + inputPath.string();
            return "";
        }

        const std::string venvPython = ".venv/bin/python3";
        const std::string pythonExe = std::filesystem::exists(venvPython) ? venvPython : "python3";
        const std::string command =
            "\"" + pythonExe + "\" ./tools/graph-nnet.py -i \"" + inputPath.string() + "\" -o \"" + filename + "\"";
        const int status = std::system(command.c_str());
        if (status != 0) {
            g_lastNetSaveError = "SVG export failed. Ensure igraph + cairocffi (or pycairo) are installed.";
            return "";
        }

        return filename;
    }

    std::string Save::saveNet(int selectedIndex)
    {
        const std::string filename = "Output/Images/indiv-" + std::to_string(selectedIndex) + ".svg";
        return saveNetAsFile(selectedIndex, filename);
    }
}