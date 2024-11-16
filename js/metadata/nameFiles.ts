import { promises as fs } from "fs";
import path from "path";
import crypto from "crypto";
import fsExtra from "fs-extra";

// Utility function to calculate SHA-256 hash of a string
const hashString = (data: string): string => {
  return crypto.createHash("sha256").update(data).digest("hex");
};

// Utility function to calculate SHA-256 hash of a file
const hashFile = async (filePath: string): Promise<string> => {
  const data = await fs.readFile(filePath);
  return hashString(data.toString("utf8"));
};

// Utility function to hash the contents of a directory iteratively
const hashDirectory = async (dirPath: string): Promise<string> => {
  const files = await fs.readdir(dirPath);
  let hash = "";

  for (const file of files) {
    const filePath = path.join(dirPath, file);
    const stat = await fs.lstat(filePath);

    if (stat.isFile()) {
      const fileHash = await hashFile(filePath);
      hash = hashString(hash + fileHash);
    } else if (stat.isDirectory()) {
      const dirHash = await hashDirectory(filePath);
      hash = hashString(hash + dirHash);
    }
  }

  return hash;
};

// Function to copy files and directories with hashed names
const copyWithHash = async (src: string, dest: string) => {
  const stat = await fs.lstat(src);

  if (stat.isFile()) {
    // if file ends in [v#] where # is a number, then use the original file name
    const hash = await hashFile(src);
    return path.join(dest, hash + path.extname(src));
  } else if (stat.isDirectory()) {
    const hash = await hashDirectory(src);
    return path.join(dest, hash);
  }
  throw new Error("Unsupported file type.");
};

// Main function to iterate through a folder and process files/directories
const processFolder = async (inputFolder: string, outputFolder: string) => {
  let files = (await fs.readdir(inputFolder)).map((file) =>
    path.join(inputFolder, file)
  );

  // pull out the files that end in [v#] where # is a number
  const versionedFiles = files.filter((file) => file.match(/.*\[v\d+\]/));
  // group by the original file name
  const groupedFiles = versionedFiles.reduce(
    (acc, file) => {
      const originalFileName = file.replace(/\[v\d+\]/, "");
      acc[originalFileName] = acc[originalFileName] || [];
      acc[originalFileName].push(file);
      return acc;
    },
    {} as Record<string, string[]>
  );
  // for each value, sort by the version number, descending
  Object.entries(groupedFiles).forEach(([key, files]) => {
    groupedFiles[key] = files.sort((a, b) => {
      const aVersion = a.match(/\[v(\d+)\]/)![1];
      const bVersion = b.match(/\[v(\d+)\]/)![1];
      return parseInt(bVersion) - parseInt(aVersion);
    });
  });

  // now remove the versioned files from the list of files
  files = files.filter((file) => !file.match(/.*\[v\d+\]/));

  for (const file of files) {
    const destFile = await copyWithHash(file, outputFolder);
    // check if the file exists in the groupedFiles
    // if it does, then copy the latest version of the file
    if (groupedFiles[file]) {
      console.log(`Copying latest version of ${file} as ${destFile}`);
      await fsExtra.copy(groupedFiles[file][0], destFile);
    } else {
      await fsExtra.copy(file, destFile);
    }
  }
};

// Command-line arguments
const args = process.argv.slice(2);
const inputFolder = args[0] || "./input";
const outputFolder = args[1] || "./output";

// Ensure output folder exists
fsExtra.ensureDirSync(outputFolder);

// Start processing
processFolder(inputFolder, outputFolder)
  .then(() => {
    console.log("Processing complete.");
  })
  .catch((err) => {
    console.error("Error processing folder:", err);
  });
