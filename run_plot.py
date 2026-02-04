#!/usr/bin/env python3
"""
Perftest Results Plotting Script
Simple bar chart for bandwidth with line overlay for cycles.
"""

import argparse
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

plt.rcParams.update({
    'figure.dpi': 200,
    'savefig.dpi': 300,
    'font.size': 14,
    'axes.titlesize': 18,
    'axes.labelsize': 16,
    'xtick.labelsize': 14,
    'ytick.labelsize': 14,
    'legend.fontsize': 14,
})

def parse_csv(filepath):
    """Parse the CSV file, skipping comment lines."""
    metadata = {}
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith('#'):
                if ':' in line:
                    key, value = line[1:].strip().split(':', 1)
                    metadata[key.strip()] = value.strip()
            else:
                break
    df = pd.read_csv(filepath, comment='#')
    return df, metadata


def format_bytes(val):
    """Format bytes to human readable."""
    if val >= 1024*1024:
        return f'{int(val/(1024*1024))}M'
    elif val >= 1024:
        return f'{int(val/1024)}K'
    else:
        return f'{int(val)}'


def plot_results(df, metadata, output_file=None, title=None):
    """Create a simple dual-axis plot: blue bars for BW, green line for cycles."""
    
    # Get data
    bytes_col = df['Bytes'].values
    bw_avg = df['BW Average (Gb/s)'].values
    
    # Get cycles column
    if 'Post Send Cycles/Iteration (ns)' in df.columns:
        cycles = df['Post Send Cycles/Iteration (ns)'].values
    elif 'Post Send Cycles/Iteration' in df.columns:
        cycles = df['Post Send Cycles/Iteration'].values
    else:
        cycles = None
    
    # X-axis labels
    x_labels = [format_bytes(b) for b in bytes_col]
    x_pos = np.arange(len(bytes_col))
    
    # Create figure
    fig, ax1 = plt.subplots(figsize=(12, 6))
    
    # Blue bars for bandwidth
    bars = ax1.bar(x_pos, bw_avg, color='steelblue', edgecolor='black', linewidth=0.5, label='Bandwidth (Gb/s)')
    ax1.set_xlabel('Message Size (Bytes)')
    ax1.set_ylabel('Bandwidth (Gb/s)', color='steelblue')
    ax1.tick_params(axis='y', labelcolor='steelblue')
    ax1.set_xticks(x_pos)
    ax1.set_xticklabels(x_labels, rotation=45, ha='right')
    
    # Red line for cycles on right y-axis
    if cycles is not None:
        ax2 = ax1.twinx()
        line, = ax2.plot(x_pos, cycles, 'o-', color='red', linewidth=2, markersize=5, label='Post Send Cycles/Iter')
        ax2.set_ylabel('Post Send Cycles/Iteration', color='red')
        ax2.tick_params(axis='y', labelcolor='red')
    
    # Title
    if title:
        plt.title(title)
    else:
        device = metadata.get('Device', '')
        plt.title(f'RDMA Write Bandwidth - {device}' if device else 'RDMA Write Bandwidth')
    
    # Legend
    from matplotlib.patches import Patch
    from matplotlib.lines import Line2D
    legend_elements = [
        Patch(facecolor='steelblue', edgecolor='black', label='Bandwidth (Gb/s)'),
    ]
    if cycles is not None:
        legend_elements.append(Line2D([0], [0], color='red', marker='o', linewidth=2, markersize=5, label='Post Send Cycles/Iter'))
    ax1.legend(handles=legend_elements, loc='upper left')
    
    plt.tight_layout()
    
    if output_file:
        plt.savefig(output_file, dpi=150, bbox_inches='tight')
        print(f"Plot saved to: {output_file}")
    else:
        plt.show()
    
    return fig


def main():
    parser = argparse.ArgumentParser(description='Plot perftest results')
    parser.add_argument('input_file', help='Input CSV file')
    parser.add_argument('-o', '--output', help='Output image file (e.g., results.png)')
    parser.add_argument('-t', '--title', help='Custom plot title')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input_file):
        print(f"Error: File '{args.input_file}' not found")
        sys.exit(1)
    
    df, metadata = parse_csv(args.input_file)
    plot_results(df, metadata, args.output, args.title)
    print("Done!")


if __name__ == '__main__':
    main()
