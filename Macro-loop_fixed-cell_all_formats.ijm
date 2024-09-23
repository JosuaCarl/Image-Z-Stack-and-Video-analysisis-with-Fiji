/*
 * Macro template to process multiple images in a folder
 */

#@ File (label = "Input directory", style = "directory") input
#@ File (label = "Output directory", style = "directory") output
#@ String (label = "File suffix", value = ".nd2") suffix

// See also Process_Folder.py for a version of this code
// in the Python scripting language.

processFolder(input, output, "");




//			FOLDER NAVIGATION FUNCTIONS			//

function processFolder(inpath, outpath, previous_path) {
	// function to scan folders/subfolders/files to find files with correct suffix
	list = getFileList(inpath);
	list = Array.sort(list);
	for (i = 0; i < list.length; i++) {
		
		if(File.isDirectory(inpath + File.separator + list[i]))

			// Create Directory branches in target output directory
			if(! File.isDirectory(outpath + previous_path + File.separator + list[i]) ){
				File.makeDirectory(outpath + previous_path + File.separator + list[i]);
			}
			
			processFolder(inpath + File.separator + list[i], outpath, previous_path + File.separator + list[i]);
		
		if(endsWith(list[i], suffix))
			processFile(previous_path, inpath, output, list[i]);
	}
}

function processFile(previous_path, input, output, file) {
	filepath = input + File.separator + file;
	outpath = output + previous_path;
	
	// Import
	print("Processing: " + filepath);
	run("Bio-Formats Importer", "open=["+ filepath + "] color_mode=Default view=Hyperstack stack_order=XYCZT");

	getDimensions (imageWidth, imageHeight, channels, slices, frames);
	if (frames == 1 && slices == 1) {
		image_analysis(previous_path, input, output, file, filepath, outpath, channels);
	}
	else if (slices == 1){
		video_analysis(previous_path, input, output, file, filepath, outpath, channels);
	}
	else {
		z_stack_analysis(previous_path, input, output, file, filepath, outpath, channels);	
	}
}



	

// 			ANALYSIS PIPELINE FUNCTIONS 			//

function image_analysis(previous_path, input, output, file, filepath, outpath, channels) {
	// function for image analysis 	
	merges = common_analysis_steps(channels);

	// Save merge
	merge_composition(merges);
	save_tiff("Composite", outpath, "Merge");
	
	// Save single files
	color_names = newArray("RR", "AF", "DAPI", "Ph2");
	for (i = 0; i < merges.length; i++) {
		save_tiff(merges[i], outpath, color_names[i]);
	}
	
	
	close("*");
}



function video_analysis(previous_path, input, output, file, filepath, outpath, channels) {
	// function for video analysis
	merges = common_analysis_steps(channels);
	
	Dialog.create("Saving options");
	Dialog.addString("Frames per second:", 1);
	Dialog.show();
	frames = Dialog.getString();

	// Save merge
	merge_composition(merges);
	save_avi("Composite", outpath, "Merge", frames);
	
	// Save single files
	color_names = newArray("TMR", "GFP", "Hoechst", "Ph2");
	for (i = 0; i < merges.length; i++) {
		save_avi(merges[i], outpath, color_names[i], frames);
	}

	close("*");
}



function z_stack_analysis(previous_path, input, output, file, filepath, outpath, channels) {
	// function for z-stack analysis
	merges = common_analysis_steps(channels);

	projection_types = newArray("Z Project", "3D Project");
	Dialog.create("How should the stack be projected ?");
	Dialog.addChoice("Projection Type:", projection_types, "Z Project");
	Dialog.show();
	projection_type = Dialog.getChoice();

	for (i = 0; i < merges.length; i++) {
		selectWindow(merges[i]);
		
		if (projection_type == "Z Project") {
			run("Z Project...", "projection=[Max Intensity]");
			merges[i] = "MAX_"+ merges[i];
		}
		else if (projection_type == "3D Project") {
			run("3D Project...", "projection=[Brightest Point] axis=Y-Axis slice=0.20 initial=0 total=360 rotation=10 lower=1 upper=255 opacity=0 surface=100 interior=50 interpolate");
			merges[i] = "Projections of "+ merges[i];
		}		
	}

	
	// Save merge
	merge_composition(merges);
	if (projection_type == "Z Project") {
		save_tiff("Composite", outpath, "Merge");
	}
	else if (projection_type == "3D Project") {
		Dialog.create("Saving options");
		Dialog.addString("Frames per second:", 5);
		Dialog.show();
		frames = Dialog.getString();
		
		save_avi("Composite", outpath, "Merge", frames);
	}
	
	// Save single channels
	color_names = newArray("TMR", "GFP", "Hoechst", "Ph2");
	for (i = 0; i < merges.length; i++) {
		if (projection_type == "Z Project") {
			save_tiff(merges[i], outpath, color_names[i]);
		}
		else if (projection_type == "3D Project") {
			save_avi(merges[i], outpath, color_names[i], frames);
		}
	}	

	close("*");
}





// 			PRINCIPAL HELPER FUNCTIONS 			//

function common_analysis_steps(channels) {
	bg_adjust();
	crop();
	scale_bar();
	split_channels();
	merges = separate_by_color(channels);

	return merges;
}


function bg_adjust() {
	// Brightness & Color Adjustment
	run("Brightness/Contrast...");
	waitForUser("B/C adjustment", "If necessary, adjust the Brightness/Contrast, then click \"OK\".");
}


function crop() {
	// Define Region of interest and crop image
	makeRectangle(1200, 1200, 1000, 1000);
	run("Specify...");
  	waitForUser("Region adjustment", "If necessary, adjust the Rectangle, then click \"OK\".");
	run("Crop");
}


function scale_bar() {
	// Add Scale Bar + Split
	run("Scale Bar...", "width=10 height=5 thickness=5 font=0 hide overlay");
}


function split_channels() {
	run("Split Channels");
}


function separate_by_color(num_channels) { 
	// Separate channels by color
	merges = newArray(num_channels);
	for (i = 1; i <= num_channels; i++) {
		
		channel_file = "C"+ i + "-" + file;
		selectImage(channel_file);
		
		run("RGB Color");
		run("Color Histogram");
		means = Table.getColumn("mean", "Results"); 	// means[0] = red, means[1] = green, means[2] = blue
		close("Histogram of *");
		close("Results");

		if (means[0] < means[2] && means[1] < means[2]) {					// separate the images into right chanels
			merges[2] = channel_file;
		} 
		else if (means[0] < means[1] && means[2] < means[1]) {
			merges[1] = channel_file;
		}	
		else if (means[1] < means[0] && means[2] < means[0]) {
			merges[0] = channel_file;
		}
		else {
			merges[3] = channel_file;
		}
	}	
	return merges;
}
	

function merge_composition(merges) { 
	// Merge Channels
	run("Merge Channels...", "c1=["+ merges[0] +"] c2=["+ merges[1] +"] c3=["+ merges[2] +"] create keep");	
	selectWindow("Composite");
	run("Scale Bar...", "width=10 height=5 thickness=5 font=0 bold overlay");
}


function save_tiff(id, outpath, suffix) {
	selectImage(id);
	run("RGB Color");
	run("Flatten");
	saveAs("Tiff", outpath + File.separator + file + "_"+ suffix + ".tif");
	close();
}

function save_avi(id, outpath, suffix, frames) { 
	selectImage(id);
	run("AVI... ", "compression=JPEG frame="+ frames + " save="+ outpath + File.separator + file + "_" + suffix + ".avi");
}

