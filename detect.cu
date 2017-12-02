using namespace std;

#include <fstream>
#include <string>
#include <cmath>

#include "opencv2/opencv.hpp"
#include "opencv2/gpu/gpu.hpp"
#include "thrust/device_vector.h"
#include "thrust/host_vector.h"

#include "polifitgsl.h"

using namespace cv;


class Lane
{
public:
	int degree;
	double *l_params;
	double *r_params;
	double filter;
	
	Lane(int d, double f) 
	{ 
		degree = d; 
		l_params = new double[d];
		r_params = new double[d];
		filter = f;
		
		for(int i = 0; i < d; i++)
		{
			l_params[i] = nan("1");
			r_params[i] = nan("1");
		}
	}
	
	~Lane()
	{
		delete[] l_params;
		delete[] r_params;
	}
	
	void update(double *l_new, double *r_new)
	{
		if (l_params[0] != l_params[0])
		{
			for (int i = 0; i < degree; i++)
			{
				l_params[i] = l_new[i];
				r_params[i] = r_new[i];
			}
		}
		else
		{
			for (int i = 0; i < degree; i++)
			{
				l_params[i] = filter * l_params[i] + (1 - filter) * l_new[i];
				r_params[i] = filter * r_params[i] + (1 - filter) * r_new[i];
			}
		}
	}
};

struct Config
{
	string video_file;
	int lane_degree;
	double lane_filter;
	int lane_start_threshold;
	int left_lane_start;
	int right_lane_start;
	int row_step;
	int col_step;
};

Config config;

Config getConfig()
{
	Config config;
	
	ifstream ifs("config.txt");
	istringstream is_file(string((std::istreambuf_iterator<char>(ifs)),
                 std::istreambuf_iterator<char>()));

	string line;
	while( getline(is_file, line) )
	{
	  istringstream is_line(line);
	  string key;
	  if( getline(is_line, key, '=') )
	  {
		string value;
		if( getline(is_line, value) ) 
		{
			if (key =="video_file") config.video_file = string(value); 
			else if (key == "lane_degree") config.lane_degree = stoi(value);
			else if (key == "lane_filter") config.lane_filter = stod(value);
			else if (key == "lane_start_threshold") config.lane_start_threshold = stoi(value);
			else if (key == "left_lane_start") config.left_lane_start = stoi(value);
			else if (key == "right_lane_start") config.right_lane_start = stoi(value);
			else if (key == "row_step") config.row_step = stoi(value);
			else if (key == "col_step") config.col_step = stoi(value);
		}
	  }
	}
	return config;
}

void thresh(Mat &img)
{
	gpu::GpuMat g1;
	gpu::GpuMat g2;
	
	g1.upload(img);
	gpu::cvtColor(g1, g2, CV_BGR2GRAY);
	
	gpu::GaussianBlur(g2, g2, Size( 7, 7 ), 1.5, 1.5 );
	gpu::threshold(g2, g2, 185, 255, THRESH_BINARY);
	g2.download(img);
}

void birdseye(Mat &img, bool undo=false)
{
	int width = img.cols;
	int height = img.rows;
	vector<Point2f> src = {Point2f(width*0.44,height*0.20), Point2f(width*0.56,height*0.20), Point2f(width*1.00,height*0.85), Point2f(width*0.00,height*0.85)};
	vector<Point2f> dst = {Point2f(width*0.20,height*0.00), Point2f(width*0.80,height*0.00), Point2f(width*0.80,height*1.00), Point2f(width*0.20,height*1.00)};
	
	Mat m;
	if (undo) m = getPerspectiveTransform(&dst[0], &src[0]);
	else m = getPerspectiveTransform(&src[0], &dst[0]);
	
	gpu::GpuMat g1(img);
	gpu::GpuMat g2;
	warpPerspective(g1, g2, m, Size(width, height));
	g2.download(img);
}	

int polynomial(double *params, int degree, double x)
{
	double val = 0;
	for (int i = 0; i < degree; i++)
	{
		val += params[i] * pow(x, i);
	}
	return (int)val;
}	

void getLanes(const Mat &img, Lane &lane)
{
	static int row_step = config.row_step;
	static int col_step = config.col_step;
	static int d = config.lane_start_threshold;
	
	Mat img_thresh = img.clone();
	thresh(img_thresh);
	birdseye(img_thresh);
	int width = img_thresh.cols;
	int height = img_thresh.rows;
	
	int left = width * config.left_lane_start / 100;
	int right = width * config.right_lane_start / 100;
	
	/*
	thrust::device_vector<double> lx;
	thrust::device_vector<double> rx;
	thrust::device_vector<double> ly;
	thrust::device_vector<double> ry;
	* */
	vector<double> lx;
	vector<double> rx;
	vector<double> ly;
	vector<double> ry;
	
	//Loop through frame rows
	for (int i = height-1; i >= 0; i-=row_step)
	{
		lx.push_back(left);
		ly.push_back(i);
		for (int j = left + d; j >= left - d; j-=col_step)
		{
			if (img_thresh.at<uchar>(i, j) == 255) 
			{
				lx.back() = j;
				left = j;
				break;
			}
		}
		
		rx.push_back(right);
		ry.push_back(i);
		for (int j = right - d; j < right + d; j+=col_step)
		{
			if (img_thresh.at<uchar>(i, j) == 255) 
			{
				rx.back() = j;
				right = j;
				break;
			}
		}
		 
	}
	
	double *l_new = new double[lane.degree];
	double *r_new = new double[lane.degree];
	polynomialfit(lx.size(), lane.degree, &ly[0], &lx[0], l_new);
	polynomialfit(rx.size(), lane.degree, &ry[0], &rx[0], r_new);
	lane.update(l_new, r_new);
}

void drawLane(Mat &img, const Lane &lane)
{
	//draw
	Mat blank(img.size(), img.type(), Scalar(0, 0, 0));
	for (int i = 0; i < img.rows; i++)
	{
		circle(blank, Point(polynomial(lane.l_params, lane.degree, i), i), 3, Scalar(150, 0, 0), 3);
		circle(blank, Point(polynomial(lane.r_params, lane.degree, i), i), 3, Scalar(150, 0, 0), 3); 
	}
	birdseye(blank, true);
	for (int i = 0; i < img.rows; i+=2)
	{
		for (int j = 0; j < img.cols; j+=2)
		{
			if (blank.at<Vec3b>(i, j)[0] == 150)
				circle(img, Point(j, i), 1, Scalar(150, 0, 0), 1);
		}
	}
}

int main(int argc, char* argv[])
{
	config = getConfig();
    Lane lane(config.lane_degree, config.lane_filter);
		
	VideoCapture cap(config.video_file); 
    if(!cap.isOpened()) return -1;
    
    namedWindow("output", 1);
    Mat frame;
    while(true)
    {
		cap >> frame;
		//-------------------------------------------------------//
		getLanes(frame, lane);
		drawLane(frame, lane);
		
		//-------------------------------------------------------//
		imshow("output", frame);
		if(waitKey(1) >= 0) break;
	}
}