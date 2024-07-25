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
    const hash = await hashFile(src);
    const destPath = path.join(dest, hash + path.extname(src));
    await fsExtra.copy(src, destPath);
  } else if (stat.isDirectory()) {
    const hash = await hashDirectory(src);
    const destPath = path.join(dest, hash);
    await fsExtra.copy(src, destPath);
  }
};

// Main function to iterate through a folder and process files/directories
const processFolder = async (inputFolder: string, outputFolder: string) => {
  const files = await fs.readdir(inputFolder);

  for (const file of files) {
    const filePath = path.join(inputFolder, file);
    await copyWithHash(filePath, outputFolder);
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
