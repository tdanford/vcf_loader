/*
 * Mechanism:
 *
 * 1) dump the sample file:
 * sample_idx, sample
 * i         , s
 *
 * 3) Stream VCF buffer:
 * variant_idx, chrom, pos, id, ref, alt, qual, filter, ns, an, misc
 * i          , s    , i  , s , s  , s  , f   , s     , i , i , s
 *
 * 3) Stream GT buffer:
 * sample_idx, variant_idx, gt
 * i         , i          , s
 *
 * 3) Stream VCF_MV buffer:
 * variant_idx, mv_idx, ac, af
 * i          , i     , i , f
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

// Standard includes
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>
#include <map>
#include <sstream>

// Is 10MB a large enough buffer for a VCF line?
// One hopes, but VCF is pathological
#define RB_SIZE 10485760

using namespace std;

char _line[RB_SIZE];

char* _inputName         = NULL;

char* _outputSamplesName = NULL;
char* _outputVarName     = NULL;
char* _outputGtName      = NULL;
char* _outputMvName      = NULL;

FILE* _inputFile         = NULL;

FILE* _outputSamplesFile = NULL;
FILE* _outputVarFile     = NULL;
FILE* _outputGtFile      = NULL;
FILE* _outputMvFile      = NULL;

size_t _variantNo  = 0;
size_t _numSamples = 0;

void usage()
{
    printf("Utility to split a VCF file into two CSV files.\n"
           "USAGE: vcf2csv [-i INPUT] samples_output var_output, gt_output, mv_output\n"
           "\t-i INPUT\tInput file. (Default = stdin).\n");
}

template <class Type>
string to_string (const Type& value)
{
    std::ostringstream repr;
    repr << value;
    return repr.str();
}

void closeFile(FILE*& file)
{
    if (file != NULL) {
        fclose(file);
    }
    file = NULL;
}

void closeFiles()
{
    closeFile(_inputFile);
    closeFile(_outputSamplesFile);
    closeFile(_outputVarFile);
    closeFile(_outputGtFile);
    closeFile(_outputMvFile);
}

void haltOnError(const char* errStr)
{
    closeFiles();
    fprintf(stderr, "ERROR: %s\n", errStr);
    usage();
    exit(EXIT_FAILURE);
}

void parseArgs(int argc, char* argv[])
{
    if (argc < 4)
    {
        haltOnError("Missing some required arguments.\n");
    }
    int i = 1;
    for ( ; i < argc; i++)
    {
        if (strcmp(argv[i], "-i") == 0)
        {
            _inputName = argv[++i];
        }
        else
        {
            break;
        }
    }
    if (i >= argc)  { haltOnError("Missing samples output filename.\n"); }
    _outputSamplesName = argv[i];
    if (++i >= argc){ haltOnError("Missing variant output filename.\n"); }
    _outputVarName = argv[i];
    if (++i >= argc){ haltOnError("Missing genotype output filename.\n"); }
    _outputGtName = argv[i];
    if (++i >= argc){ haltOnError("Missing multival output filename.\n"); }
    _outputMvName = argv[i];
}

void openFiles()
{
    if (_inputName == NULL) {
        _inputFile = stdin;
    } else {
        _inputFile = fopen(_inputName, "r");
        if (_inputFile == NULL) {
            haltOnError("Failed to open specified VCF input file.");
        }
    }
    _outputVarFile = fopen(_outputVarName, "w");
    if (_outputVarFile == NULL) {
        haltOnError("Failed to open variation output file.");
    }

    _outputGtFile = fopen(_outputGtName, "w");
    if (_outputGtFile == NULL) {
        haltOnError("Failed to open genotype output file.");
    }

    _outputMvFile = fopen(_outputMvName, "w");
    if (_outputMvFile == NULL) {
        haltOnError("Failed to open multival output file.");
    }
}

vector<string> parseHeader(char* head)
{
    char* pTok = strtok(head, "\t\n");
    size_t col = 0;
    vector<string> result;
    while (pTok != NULL)
    {
        if (++col > 9)
        {
            string tok(pTok);
            result.push_back(tok);
        }
        pTok = strtok(NULL, "\t\n");
    }
    _numSamples = result.size();
    return result;
}

void dumpSamples(vector<string> const& sampleNames)
{
    _outputSamplesFile = fopen(_outputSamplesName, "w");
    if (_outputSamplesFile == NULL)
    {
        haltOnError("Failed to open variation output file.");
    }
    for (size_t i=0; i<_numSamples; ++i)
    {
        fprintf(_outputSamplesFile, "%lu\t%s\n", i, sampleNames[i].c_str());
    }
    closeFile(_outputSamplesFile);
}

size_t allele_count(char* tok)
{
    size_t count = 2;
    for (size_t i=0; tok[i] != '\0'; i++) {
        if (tok[i] == ',') ++count;
    }
    return count;
}

char* parse_format(char* fmt)
{
    if (fmt[0] == 'G' && fmt[1] == 'T') {
        if (fmt[2] == '\0') return &fmt[2];
        if (fmt[2] == ':') fmt = &fmt[3];
    }
    return fmt;
}

inline void multValToVector(char* multVal, vector<string>& values)
{
    char *ch = multVal;
    ostringstream out;
    bool gotStuff = false;
    while ((*ch) != '\0')
    {
        if ((*ch) == ',')
        {
            values.push_back(out.str());
            out.str("");
            gotStuff = false;
        }
        else
        {
            out<<(*ch);
            gotStuff = true;
        }
        ++ch;
    }
    if(gotStuff)
    {
        values.push_back(out.str());
    }
 }

inline void writeMultVals( vector<string> const& ac,
                           vector<string> const& af)
{
    size_t const acSize  = ac.size();
    size_t const afSize  = af.size();
    size_t maxSize = acSize;
    if( afSize > maxSize) { maxSize = afSize; }
    if (maxSize == 0)
    {
        fprintf(_outputMvFile, "%lu\t0\t\t\n", _variantNo);
        return;
    }
    for (size_t i=0; i<maxSize; ++i)
    {
        fprintf(_outputMvFile, "%lu\t%lu\t", _variantNo, i);
        if( i < acSize ) { fprintf(_outputMvFile, "%s\t", ac[i].c_str()); }
        else             { fprintf(_outputMvFile, "\t");                  }
        if( i < afSize ) { fprintf(_outputMvFile, "%s\t", af[i].c_str()); }
        else             { fprintf(_outputMvFile, "\t");                  }
        fprintf(_outputMvFile, "\n");
    }
}

inline void parseInfo(char* info)
{
    if (info[0]=='\0')
    {
        fprintf(_outputVarFile, "\t\t\n");
        return;
    }
    char nil = '\0';
    char *ns = &nil;
    char *an = &nil;
    vector<string> ac;
    vector<string> af;
    char *token = strtok(info, ";");
    ostringstream infoBuf;
    while ( token != NULL )
    {
        if      (token[0]=='N' && token[1]=='S' && token[2]=='=' )
        {
            ns = &token[3];
        }
        else if (token[0]=='A' && token[1]=='N' && token[2]=='=' )
        {
            an = &token[3];
        }
        else if (token[0]=='A' && token[1]=='C' && token[2]=='=' )
        {
            multValToVector(&token[3], ac);
        }
        else if (token[0]=='A' && token[1]=='F' && token[2]=='=' )
        {
            multValToVector(&token[3], af);
        }
        else
        {
            infoBuf << token << ";";
        }
        token = strtok(NULL, ";");
    }
    fprintf(_outputVarFile, "%s\t%s\t%s\n", ns, an, infoBuf.str().c_str());
    writeMultVals(ac, af);
}

void parseLine(char* line)
{
    char* chrom  = strtok(line, "\t");
    char* pos    = strtok(NULL, "\t");
    char* id     = strtok(NULL, "\t");
    char* ref    = strtok(NULL, "\t");
    char* alt    = strtok(NULL, "\t");
    char* qual   = strtok(NULL, "\t");
    char* filter = strtok(NULL, "\t");
    if (strcmp(id,  ".") == 0)    { id[0]    ='\0'; }
    if (strcmp(qual,".") == 0)    { qual[0]  ='\0'; }
    if (strcmp(filter,".") == 0)  { filter[0]='\0'; }
    fprintf(_outputVarFile, "%lu\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t", _variantNo, chrom, pos, id, ref, alt, qual, filter);
    char* info   = strtok(NULL, "\t");
    if (strcmp(info,".") == 0)    { info[0]  ='\0'; }
    char* nextToken = info + strlen(info) + 1;
    parseInfo(info);
    strtok(nextToken, "\t"); //format
    char* gt = strtok(NULL, "\t");
    size_t gtIdx = 0;
    while (gt != NULL)
    {
        fprintf(_outputGtFile, "%lu\t%lu\t%s\n", _variantNo, gtIdx, gt);
        gt = strtok(NULL, "\t\n");
        ++gtIdx;
    }
    if (gtIdx != _numSamples)
    {
        haltOnError("Encountered data line with an unexpected number of GT; exiting");
    }
}

int main(int argc, char* argv[])
{
    parseArgs(argc, argv);
    openFiles();
    while (fgets(_line, RB_SIZE, _inputFile) != NULL)
    {
        if (strlen(_line) == 1)
        {
            continue;
        }
        else if (_line[0] == '#')
        {
            if (_line[1] == '#')
            {
                continue;
            }
            vector<string> samples = parseHeader(_line);
            if ( _numSamples == 0)
            {
                haltOnError("Found no samples in the header line");
            }
            dumpSamples(samples);
        }
        else
        {
            parseLine(_line);
            _variantNo ++;
        }
    }
    closeFiles();
    exit(EXIT_SUCCESS);
}
